library fireflutter_in_app_purchase;

import 'dart:io';

import 'package:fireflutter/fireflutter.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// const List<String> _kProductIds = <String>[
//   _kConsumableId,
//   'upgrade',
//   'subscription'
// ];

const String statusPending = 'pending';
const String statusSuccess = 'success';
const String statusFailure = 'failure';

const String MISSING_PRODUCTS = 'MISSING_PRODUCTS';

class FireflutterInAppPurchase {
  /// Product items to sell to users.
  // RxList products = [].obs;

  FireflutterInAppPurchase({@required FireFlutter inject}) : _ff = inject;
  FireFlutter _ff;

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
  // ignore: close_sinks
  PublishSubject success = PublishSubject<PurchaseDetails>();

  InAppPurchaseConnection connection = InAppPurchaseConnection.instance;

  String _pendingPurchaseDocumentId;

  init({
    @required Set<String> productIds,
    List<String> consumableIds,
    bool autoConsume = true,
  }) {
    // print('Payment::init');
    this._productIds = productIds;
    this.consumableIds = consumableIds;
    this.autoConsume = autoConsume;
    _initIncomingPurchaseStream();
    _initPayment();
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
      purchaseDetailsList.forEach(
        (PurchaseDetails purchaseDetails) async {
          // All purchase event(pending, success, or cancelling) comes here.

          // if it's pending, this mean, the user just started to pay.
          // previous app session pending purchase is not `PurchaseStatus.pending`. It is either
          // `PurchaseStatus.purchased` or `PurchaseStatus.error`
          if (purchaseDetails.status == PurchaseStatus.pending) {
            pending.add(purchaseDetails);
            _recordPending(purchaseDetails);
          } else {
            if (purchaseDetails.status == PurchaseStatus.error) {
              error.add(purchaseDetails);
              if (Platform.isIOS) {
                connection.completePurchase(purchaseDetails);
              }
              _recordFailure(purchaseDetails);
            } else if (purchaseDetails.status == PurchaseStatus.purchased) {
              // for android & consumable product only.
              if (Platform.isAndroid) {
                if (!autoConsume &&
                    consumableIds.contains(purchaseDetails.productID)) {
                  await connection.consumePurchase(purchaseDetails);
                }
              }
              if (purchaseDetails.pendingCompletePurchase) {
                await connection.completePurchase(purchaseDetails);
                _recordSuccess(purchaseDetails);
                success.add(purchaseDetails);
              }
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
    DocumentReference doc = await _ff.db.collection('purchase').add({
      'status': statusPending,
      'uid': _ff.user.uid,
      'displayName': _ff.user.displayName,
      'email': _ff.user.email,
      'phoneNumber': _ff.user.phoneNumber,
      'photoURL': _ff.user.photoURL,
      'productDetails': {
        'id': productDetails.id,
        'title': productDetails.title,
        'description': productDetails.description,
        'price': productDetails.price,
        'hashCode': productDetails.hashCode,
      },
      'purchaseDetails': {
        'productID': purchaseDetails.productID,
        'pendingCompletePurchase': purchaseDetails.pendingCompletePurchase,
        'verificationData.localVerificationData':
            purchaseDetails.verificationData.localVerificationData,
        'verificationData.serverVerificationData':
            purchaseDetails.verificationData.serverVerificationData,
        'hashCode': purchaseDetails.hashCode,
      },
      'endAt': FieldValue.serverTimestamp(),
    });
    _pendingPurchaseDocumentId = doc.id;
  }

  _recordFailure(PurchaseDetails purchaseDetails) async {
    _ff.db.collection('purchase').doc(_pendingPurchaseDocumentId).update({
      'status': statusFailure,
      'endAt': FieldValue.serverTimestamp(),
    });
  }

  _recordSuccess(PurchaseDetails purchaseDetails) async {
    ProductDetails productDetails = products[purchaseDetails.productID];
    _ff.db.collection('purchase').doc(_pendingPurchaseDocumentId).update({
      'status': statusSuccess,
      'purchaseDetails.transactionDate': purchaseDetails.transactionDate,
      'purchaseDetails.purchaseID': purchaseDetails.purchaseID,
      'purchaseDetails.skPaymentTransaction.payment.applicationUsername':
          purchaseDetails.skPaymentTransaction.payment.applicationUsername,
      'purchaseDetails.skPaymentTransaction.payment.productIdentifier':
          purchaseDetails.skPaymentTransaction.payment.productIdentifier,
      'purchaseDetails.skPaymentTransaction.payment.quantity':
          purchaseDetails.skPaymentTransaction.payment.quantity,
      'purchaseDetails.skPaymentTransaction.payment.hashCode':
          purchaseDetails.skPaymentTransaction.payment.hashCode,
      'purchaseDetails.skPaymentTransaction.transactionIdentifier':
          purchaseDetails.skPaymentTransaction.transactionIdentifier,
      'purchaseDetails.verificationData.localVerificationData.success':
          purchaseDetails.verificationData.localVerificationData,
      'purchaseDetails.verificationData.serverVerificationData.success':
          purchaseDetails.verificationData.serverVerificationData,

      'purchaseDetails.pendingCompletePurchase':
          purchaseDetails.pendingCompletePurchase,

      'productDetails.skProduct.price': productDetails.skProduct.price,
      'productDetails.skProduct.priceLocale.currencyCode':
          productDetails.skProduct.priceLocale.currencyCode,
      'productDetails.skProduct.productIdentifier':
          productDetails.skProduct.productIdentifier,
      // 'skuDetail.sku': productDetails.skuDetail.sku,
      // 'skuDetail.price': productDetails.skuDetail.price,
      // 'skuDetail.priceCurrencyCode': productDetails.skuDetail.priceCurrencyCode,
      // 'skuDetail.originalPrice': productDetails.skuDetail.originalPrice,
      // 'skuDetail.type': productDetails.skuDetail.type,
      'endAt': FieldValue.serverTimestamp(),
    });
  }

  Future buyConsumable(ProductDetails product) async {
    PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: _ff.user.uid,
    );

    await connection.buyConsumable(
      purchaseParam: purchaseParam,
    );
  }
}
