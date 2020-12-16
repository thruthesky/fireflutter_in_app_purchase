library fireflutter_in_app_purchase;

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// const List<String> _kProductIds = <String>[
//   _kConsumableId,
//   'upgrade',
//   'subscription'
// ];

class SessionStatus {
  static final String pending = 'pending';
  static final String success = 'success';
  static final String failure = 'failure';
}

const String MISSING_PRODUCTS = 'MISSING_PRODUCTS';
const String PURCHASE_SESSION_NOT_FOUND = 'PURCHASE_SESSION_NOT_FOUND';

class PurchaseDocumentProductDetails {
  String id;
  String price;
  String title;
  Map skProduct;
  PurchaseDocumentProductDetails({
    this.id,
    this.price,
    this.title,
    this.skProduct,
  });
}

class SkPaymentTransationPayment {
  String applicationUserName;
  int quantity;
  String productIdentifier;
  SkPaymentTransationPayment(payment) {
    if (payment == null) return;
    this.applicationUserName = payment['applicationUserName'];
    this.quantity = payment['quantity'];
    this.productIdentifier = payment['productIdentifier'];
  }
}

class SkPaymentTransation {
  SkPaymentTransationPayment payment;
  SkPaymentTransation(payment)
      : this.payment = SkPaymentTransationPayment(payment);
}

class PurchaseDocumentPurchaseDetails {
  String purchaseID;
  String productID;
  SkPaymentTransation skPaymentTransaction;
  PurchaseDocumentPurchaseDetails({
    this.purchaseID,
    this.productID,
    skPaymentTransaction,
  }) : this.skPaymentTransaction = SkPaymentTransation(skPaymentTransaction);
}

/// Purchase information
///
/// TODO complete adding the purchase properties from `/puchase/{doc-id}`
class PurchaseSession {
  /// [id] is the document id of Firestore
  String id;

  /// applicationUserName is used as session id.
  String applicationUserName;
  String get sessionId => applicationUserName;

  /// [beginAt] is the timestamp when the purchase session began.
  Timestamp beginAt;

  /// [endAt] is the timestamp when the purchase session ended.
  Timestamp endAt;
  String status;

  /// User's displayName, email, phoneNumber, photoURL, uid
  String displayName;
  String email;
  String phoneNumber;
  String photoURL;
  String uid;

  PurchaseDocumentProductDetails productDetails;
  PurchaseDocumentPurchaseDetails purchaseDetails;

  /// [data] hold the document data.
  ///
  /// If you put your costum data on the purchase document, you will be
  /// able to access your data through this variable.
  Map<String, dynamic> data;

  ///
  PurchaseSession({
    this.data,
    this.id,
    this.applicationUserName,
    this.beginAt,
    this.displayName,
    this.email,
    this.endAt,
    this.phoneNumber,
    this.photoURL,
    this.status,
    this.uid,
    this.productDetails,
    this.purchaseDetails,
  });
  factory PurchaseSession.fromSnapshot(snapshot) {
    final data = snapshot.data();
    data['id'] = snapshot.id;
    return PurchaseSession(
      data: data,
      id: data['id'],
      applicationUserName: data['applicationUserName'],
      beginAt: data['beginAt'],
      displayName: data['displayName'],
      email: data['email'],
      endAt: data['endAt'],
      phoneNumber: data['phoneNumber'],
      photoURL: data['photoURL'],
      status: data['status'],
      uid: data['uid'],
      productDetails: PurchaseDocumentProductDetails(
        id: data['productDetails']['id'],
        price: data['productDetails']['price'],
        title: data['productDetails']['title'],
        skProduct: data['productDetails']['skProduct'],
      ),
      purchaseDetails: PurchaseDocumentPurchaseDetails(
        productID: data['purchaseDetails']['productID'],
        purchaseID: data['purchaseDetails']['purchaseID'],
        skPaymentTransaction: data['purchaseDetails']['skPaymentTransaction'],
      ),
    );
  }
}

/// In app purchase
class FireflutterInAppPurchase {
  /// Product items to sell to users.
  // RxList products = [].obs;

  get db => FirebaseFirestore.instance;
  get user => FirebaseAuth.instance.currentUser;
  CollectionReference get purchaseCol => db.collection('purchase');

  Map<String, ProductDetails> products = {};
  List<String> missingIds = [];

  Set<String> _productIds = {};

  /// [productReady] is being fired after it got product list from the server.
  ///
  /// The app can display product after this event.
  BehaviorSubject productReady = BehaviorSubject.seeded(null);

  /// It autoconsume the consumable product by default.
  /// If you set it to false, you must manually mark the product as consumed to enable another purchase (Android only).
  bool autoConsume;

  /// On `android` you need to specify which is consumable. By listing the product ids
  List consumableIds = [];

  /// [pending] event will be fired on incoming purchases or previous purchase of previous app session.
  ///
  /// The app can show a UI to display the payment is on going.
  ///
  /// Note that [pending] is `PublishSubject`. This means, the app must listen [pending] before invoking `init()`
  // ignore: close_sinks
  PublishSubject pending = PublishSubject<PurchaseDetails>();

  /// [error] event will be fired when any of purchase fails(or errors). This
  /// includes cancellation, verification failure, and other errors.
  ///
  /// Note that [error] is `PublishSubject`. This means, the app must listen [error] before invoking `init()`
  // ignore: close_sinks
  PublishSubject error = PublishSubject<PurchaseDetails>();

  /// [success] event will be fired after the purchase has made and the the app can
  /// deliver the purchase to user.
  ///
  /// Not that the app can then, connect to backend server to verifiy if the
  /// payment was really made and deliver products to user on the backend.
  ///
  /// Note that, the event data of [success] is `PurchaseSession`
  ///
  // ignore: close_sinks
  PublishSubject<PurchaseSession> success = PublishSubject<PurchaseSession>();

  InAppPurchaseConnection connection = InAppPurchaseConnection.instance;

  // String _pendingPurchaseDocumentId;

  /// Initialize payment
  ///
  /// Attention, [init] should be called after Firebase initialization since
  /// it may access database for pending purchase from previous app session.
  Future init({
    @required Set<String> productIds,
    List<String> consumableIds,
    bool autoConsume = true,
  }) async {
    // print('Payment::init');
    this._productIds = productIds;
    this.consumableIds = consumableIds;
    this.autoConsume = autoConsume;
    _initIncomingPurchaseStream();
    await _initPayment();
  }

  /// Subscribe to any incoming(or pending) purchases
  ///
  /// It's important to listen as soon as possible to avoid losing events.
  _initIncomingPurchaseStream() {
    /// Listen to any pending & incoming purchases.
    ///
    /// If app crashed right after purchase but the purchase has not yet
    /// delivered, then, the purchase will be notified here with
    /// `PurchaseStatus.pending`. This is confirmed on iOS.
    ///
    /// Note, that this listener will be not unscribed since it should be
    /// lifetime listener
    ///
    /// Note, for the previous app session pending purchase, listener event will be called
    /// one time only on app start after closing. Hot-Reload or Full-Reload is not working.
    connection.purchaseUpdatedStream.listen((dynamic purchaseDetailsList) {
      print('purchaseUpdatedStream.listen( ${purchaseDetailsList.length} )');
      purchaseDetailsList.forEach(
        (PurchaseDetails purchaseDetails) async {
          print('purchaseDetailsList.forEach( ... )');
          // All purchase event(pending, success, or cancelling) comes here.

          // if it's pending, this mean, the user just started to pay.
          // previous app session pending purchase is not `PurchaseStatus.pending`. It is either
          // `PurchaseStatus.purchased` or `PurchaseStatus.error`
          if (purchaseDetails.status == PurchaseStatus.pending) {
            print('=> pending on purchaseUpdatedStream');
            pending.add(purchaseDetails);
            _recordPending(purchaseDetails);
          } else if (purchaseDetails.status == PurchaseStatus.error) {
            print('=> error on purchaseUpdatedStream');
            error.add(purchaseDetails);
            _recordFailure(purchaseDetails);
            if (Platform.isIOS) {
              connection.completePurchase(purchaseDetails);
            }
          } else if (purchaseDetails.status == PurchaseStatus.purchased) {
            print('=> purchased on purchaseUpdatedStream');
            // for android & consumable product only.
            if (Platform.isAndroid) {
              if (!autoConsume &&
                  consumableIds.contains(purchaseDetails.productID)) {
                await connection.consumePurchase(purchaseDetails);
              }
            }
            if (purchaseDetails.pendingCompletePurchase) {
              await connection.completePurchase(purchaseDetails);
              final session = await _recordSuccess(purchaseDetails);
              success.add(session);
            }
          }
        },
      );
    }, onDone: () {
      print('onDone:');
    }, onError: (error) {
      print('onError: error on listening:');
      print(error);
    });
  }

  /// Init the in-app-purchase
  ///
  /// - Get products based on the [productIds]
  _initPayment() async {
    final bool available = await connection.isAvailable();

    if (available) {
      ProductDetailsResponse response =
          await connection.queryProductDetails(_productIds);

      /// Check if any of given product id(s) are missing.
      if (response.notFoundIDs.isNotEmpty) {
        missingIds = response.notFoundIDs;
      }

      response.productDetails
          .forEach((product) => products[product.id] = product);

      productReady.add(products);
    } else {
      print('===> InAppPurchase connection is NOT avaible!');
    }
  }

  _recordPending(PurchaseDetails purchaseDetails) async {
    ProductDetails productDetails = products[purchaseDetails.productID];
    await db.collection('purchase').add({
      'applicationUserName': applicationUserName,
      'status': SessionStatus.pending,
      'uid': user.uid,
      'displayName': user.displayName,
      'email': user.email,
      'phoneNumber': user.phoneNumber,
      'photoURL': user.photoURL,
      'productDetails': {
        'id': productDetails.id,
        'title': productDetails.title,
        'description': productDetails.description,
        'price': productDetails.price,
      },
      'purchaseDetails': {
        'productID': purchaseDetails.productID,
        'pendingCompletePurchase': purchaseDetails.pendingCompletePurchase,
        'verificationData': {
          'localVerificationData': {
            'pending': purchaseDetails.verificationData.localVerificationData,
          },
          'serverVerificationData': {
            'pending': purchaseDetails.verificationData.serverVerificationData,
          },
        },
      },
      'beginAt': FieldValue.serverTimestamp(),
    });
    // _pendingPurchaseDocumentId = doc.id;
  }

  Future<PurchaseSession> getPurchaseSession(
      PurchaseDetails purchaseDetails) async {
    String id =
        purchaseDetails.skPaymentTransaction.payment.applicationUsername;
    return getPurchaseSessionBySessionId(id);
  }

  Future<PurchaseSession> getPurchaseSessionBySessionId(String id) async {
    QuerySnapshot querySnapshot = await purchaseCol
        .where('uid', isEqualTo: user.uid)
        .where('applicationUserName', isEqualTo: id)
        .get();
    if (querySnapshot.size == 0) {
      throw PURCHASE_SESSION_NOT_FOUND;
    }
    final session = PurchaseSession.fromSnapshot(querySnapshot.docs[0]);

    return session;
  }

  _recordFailure(PurchaseDetails purchaseDetails) async {
    print(purchaseDetails);

    final session = await getPurchaseSession(purchaseDetails);

    purchaseCol.doc(session.id).update({
      'status': SessionStatus.failure,
      'purchaseDetails.productID': purchaseDetails.productID,
      'purchaseDetails.skPaymentTransaction.transactionIdentifier':
          purchaseDetails.skPaymentTransaction.transactionIdentifier,
      'endAt': FieldValue.serverTimestamp(),
    });
  }

  Future<PurchaseSession> _recordSuccess(
      PurchaseDetails purchaseDetails) async {
    ProductDetails productDetails = products[purchaseDetails.productID];
    final session = await getPurchaseSession(purchaseDetails);
    await db.collection('purchase').doc(session.id).update({
      'status': SessionStatus.success,
      'purchaseDetails.transactionDate': purchaseDetails.transactionDate,
      'purchaseDetails.purchaseID': purchaseDetails.purchaseID,
      'purchaseDetails.skPaymentTransaction.payment.applicationUsername':
          purchaseDetails.skPaymentTransaction.payment.applicationUsername,
      'purchaseDetails.skPaymentTransaction.payment.productIdentifier':
          purchaseDetails.skPaymentTransaction.payment.productIdentifier,
      'purchaseDetails.skPaymentTransaction.payment.quantity':
          purchaseDetails.skPaymentTransaction.payment.quantity,
      'purchaseDetails.skPaymentTransaction.transactionIdentifier':
          purchaseDetails.skPaymentTransaction.transactionIdentifier,
      'purchaseDetails.skPaymentTransaction.transactionTimeStamp':
          purchaseDetails.skPaymentTransaction.transactionTimeStamp,
      'purchaseDetails.verificationData.localVerificationData.success':
          purchaseDetails.verificationData.localVerificationData,
      'purchaseDetails.verificationData.serverVerificationData.success':
          purchaseDetails.verificationData.serverVerificationData,

      'purchaseDetails.pendingCompletePurchase':
          purchaseDetails.pendingCompletePurchase,

      'productDetails.price': productDetails.price,
      'productDetails.skProduct.price': productDetails.skProduct.price,

      'productDetails.skProduct.priceLocale.currencyCode':
          productDetails.skProduct.priceLocale.currencyCode,

      'productDetails.skProduct.priceLocale.currencySymbol':
          productDetails.skProduct.priceLocale.currencySymbol,

      'productDetails.skProduct.productIdentifier':
          productDetails.skProduct.productIdentifier,
      // 'skuDetail.sku': productDetails.skuDetail.sku,
      // 'skuDetail.price': productDetails.skuDetail.price,
      // 'skuDetail.priceCurrencyCode': productDetails.skuDetail.priceCurrencyCode,
      // 'skuDetail.originalPrice': productDetails.skuDetail.originalPrice,
      // 'skuDetail.type': productDetails.skuDetail.type,
      'endAt': FieldValue.serverTimestamp(),
    });
    return session;
  }

  /// Unique purchase session id
  ///
  /// Since there is no way to determine the same purchase session when the
  /// purchase has finished.
  ///
  /// TODO find the right way to determine the purchase session.
  ///
  /// Purchase session id
  ///
  /// 문제: 세션 A 가 진행 중에 앱이 종료된 경우, 앱 재 실행 후 세션 A 가 계속 진행되는데,
  /// 이 때, DB 에 많은 세션 정보 중 어떤 것이 세션 A 인지 알 수 있는 방법이 없다.
  /// 그래서 아래와 같이 고유 값을 생성하고 `buyConsumable()` 의 [applicationUserName]
  /// 속성에 저장하고, DB 에 보관한다. 그리고 이 값을 바탕으로 해당 정보를 참조하면 된다.
  String _applicationUserName;
  String get _generateApplicationUserName {
    _applicationUserName =
        user.uid + '-' + DateTime.now().millisecondsSinceEpoch.toString();
    return _applicationUserName;
  }

  String get applicationUserName => _applicationUserName;
  Future buyConsumable(ProductDetails product) async {
    PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: _generateApplicationUserName,
    );

    await connection.buyConsumable(
      purchaseParam: purchaseParam,
    );
  }

  /// Returns the Collection Query to get the login user's success purchases.
  Future get getMyPurchases async {
    return db
        .collection('purchase')
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'success')
        .orderBy('beginAt')
        .get();
  }
}
