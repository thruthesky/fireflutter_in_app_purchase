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

class FireflutterInAppPurchase {
  /// Product items to sell to users.
  // RxList products = [].obs;

  FireflutterInAppPurchase({@required FireFlutter inject}) : _ff = inject;
  FireFlutter _ff;

  List products = [];
  Set<String> productIds = {};
  BehaviorSubject productStream = BehaviorSubject.seeded([]);

  /// It autoconsume the consumable product by default.
  /// If you set it to false, you must manually mark the product as consumed to enable another purchase (Android only).
  bool autoConsume;

  /// On `android` you need to specify which is consumable. By listing the product ids
  List consumableIds = [];

  /// [pending] event will be fired on any of pending purchase which will
  /// happends on the pending purchases from previous app session or new
  /// incoming purchase.
  /// [error] event will be fired when any of purchase fails(or errors). This
  /// includes cancellation, verification failure, and other errors.
  /// [verified] event will be fired when the purchase has verified and you can
  /// deliver the purchase to user.
  // ignore: close_sinks
  PublishSubject pending = PublishSubject<PurchaseDetails>();
  // ignore: close_sinks
  PublishSubject error = PublishSubject<PurchaseDetails>();
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
    this.productIds = productIds;
    this.consumableIds = consumableIds;
    this.autoConsume = autoConsume;
    _initIncomingPurchaseStream();
    _initPayment();
    // _pastPurchases();
  }

  /// Subscribe to any incoming purchases at app initialization. These can
  /// propagate from either storefront so it's important to listen as soon as
  /// possible to avoid losing events.
  _initIncomingPurchaseStream() {
    final Stream purchaseUpdates = connection.purchaseUpdatedStream;

    /// Listen to any incoming purchases AND any pending purchase from previous app session.
    /// * For instance, app crashed right after purchase and the purchase has not yet delivered,
    /// * Then, the purchase will be notified here with `PurchaseStatus.pending`. This is confirmed on iOS.
    /// No need to unscribe since it is lifetime listener
    ///
    /// ! This is being called only on app start after closing. Hot-Reload or Full-Reload is not working.
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
              bool valid = await _verifyPurchase(purchaseDetails);
              if (valid) {
                deliverProduct(purchaseDetails);
              } else {
                _handleInvalidPurchase(purchaseDetails);
                return;
              }
            }

            if (Platform.isAndroid) {
              if (!autoConsume &&
                  consumableIds.contains(purchaseDetails.productID)) {
                await InAppPurchaseConnection.instance
                    .consumePurchase(purchaseDetails);
              }
            }
            if (purchaseDetails.pendingCompletePurchase) {
              await InAppPurchaseConnection.instance
                  .completePurchase(purchaseDetails);
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
  /// - Check if in-app-purchase is availalbe
  /// - Check if the product ids are available
  ///
  _initPayment() async {
    /// For IOS Testing and need to clean the pending purchase.
    /// https://github.com/flutter/flutter/issues/53534#issuecomment-674069878
    // if (Platform.isIOS) {
    //   final transactions = await SKPaymentQueueWrapper().transactions();
    //   for (final transaction in transactions) {
    //     try {
    //       if (transaction.transactionState !=
    //           SKPaymentTransactionStateWrapper.purchasing) {
    //         await SKPaymentQueueWrapper().finishTransaction(transaction);
    //       }
    //     } catch (e) {
    //       print(e);
    //     }
    //   }
    // }

    final bool available = await InAppPurchaseConnection.instance.isAvailable();

    if (available) {
      // print('In app purchase is ready');

      final ProductDetailsResponse response = await InAppPurchaseConnection
          .instance
          .queryProductDetails(productIds);

      if (response.notFoundIDs.isNotEmpty) {
        // Handle the error.
        print("Product IDs that are not found from store.");
        print(response.notFoundIDs);
      }
      products = response.productDetails;
      productStream.add(products);
      print('found products:');
      print(products.map((e) => e.id).toList());
    } else {
      print('In app purchase is NOT ready');
      // Get.snackbar('Error', 'App cannot acceess to Store.');
    }
  }

  /// todo verify the purchase if that's real purchase or a fake.
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) {
    // IMPORTANT!! Always verify a purchase before delivering the product.
    // For the purpose of an example, we directly return true.
    print("_verifyPurchase");
    verified.add(purchaseDetails);
    return Future<bool>.value(true);
  }

  /// todo if the purchase is invalid, alert it to users.
  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    // handle invalid purchase here if  _verifyPurchase` failed.
  }

  /// todo connect to Functions and open boxes.
  void deliverProduct(PurchaseDetails purchaseDetails) async {
    // IMPORTANT!! Always verify a purchase purchase details before delivering the product.
    if (consumableIds.contains(purchaseDetails.productID)) {
      // await ConsumableStore .save(purchaseDetails.purchaseID);
      // List<String> consumables = await ConsumableStore.load();
      // setState(() {
      //   _purchasePending = false;
      //   _consumables = consumables;
      // });
    } else {
      // setState(() {
      //   _purchases.add(purchaseDetails);
      //   _purchasePending = false;
      // });
    }
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
