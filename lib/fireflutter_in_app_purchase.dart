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

  @Deprecated('use products map')
  List _products = [];
  Map<String, ProductDetails> products = {};
  List<String> missingIds = [];

  List get getProducts => _products;
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

  /// [pending] event will be fired on any of pending purchase which will
  /// happends on the pending purchases from previous app session or new
  /// incoming purchase.
  /// Note that [pending] is `PublishSubject`. This means, the app must listen [pending] before invoking `init()`
  // ignore: close_sinks
  PublishSubject pending = PublishSubject<PurchaseDetails>();

  /// [error] event will be fired when any of purchase fails(or errors). This
  /// includes cancellation, verification failure, and other errors.
  ///
  /// Note that [error] is `PublishSubject`. This means, the app must listen [error] before invoking `init()`
  // ignore: close_sinks
  PublishSubject error = PublishSubject<PurchaseDetails>();

  /// [verified] event will be fired when the purchase has verified and you can
  /// deliver the purchase to user.
  // ignore: close_sinks
  PublishSubject verified = PublishSubject<PurchaseDetails>();
  // ignore: close_sinks
  PublishSubject pastPurchasesError = PublishSubject<PurchaseDetails>();

  InAppPurchaseConnection connection = InAppPurchaseConnection.instance;

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
    final Stream purchaseUpdates = connection.purchaseUpdatedStream;

    /// Listen to any pending & incoming purchases.
    ///
    /// If app crashed right after purchase but the purchase has not yet
    /// delivered, then, the purchase will be notified here with
    /// `PurchaseStatus.pending`. This is confirmed on iOS.
    ///
    /// Note, that this listener will be not unscribed since it should be
    /// lifetime listener
    ///
    /// Note, if there is a pending purchase, this is being called only
    /// one time on app start after closing. Hot-Reload or Full-Reload is not working.
    purchaseUpdates.listen((dynamic purchaseDetailsList) {
      // print('purchaseUpdates.listen((dynamic purchaseDetailsList) =>');
      purchaseDetailsList.forEach(
        (PurchaseDetails purchaseDetails) async {
          if (purchaseDetails.status == PurchaseStatus.pending) {
            /// Pending purchase from previous app session and new incoming pending purchase will come here.
            // showPendingUI();
            pending.add(purchaseDetails);
          } else {
            if (purchaseDetails.status == PurchaseStatus.error) {
              error.add(purchaseDetails);
            } else if (purchaseDetails.status == PurchaseStatus.purchased) {
              if (Platform.isAndroid) {
                if (!autoConsume &&
                    consumableIds.contains(purchaseDetails.productID)) {
                  await connection.consumePurchase(purchaseDetails);
                }
              }
              if (purchaseDetails.pendingCompletePurchase) {
                await connection.completePurchase(purchaseDetails);
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

  /// todo if the purchase is invalid, alert it to users.
  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    // handle invalid purchase here if  _verifyPurchase` failed.
  }

//   _recordPending() async {
//     _ff.db.collection('purchase').add({
//       'status': statusPending,
//       'uid': _ff.user.uid,
//       'displayName': _ff.user.displayName,
//       'email': _ff.user.email,
//       'phoneNumber': _ff.user.phoneNumber,
//       'photoURL': _ff.user.photoURL,
//       'productId': '',
//     });
//   }
//   _recordFailure() async {
//     _ff.db.collection('purchase').doc('...purchaseId...').update({ 'status': statusFailure, 'endAt': FieldValue.serverTimestamp() });
//   }
//   _recordSuccess() async {
// _ff.db.collection('purchase').doc('...purchaseId...').update({ 'status': statusSuccess, 'endAt': FieldValue.serverTimestamp() });
//   }

}
