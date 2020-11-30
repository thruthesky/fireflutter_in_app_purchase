library fireflutter_in_app_purchase;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

const bool _kAutoConsume = true;

const String _kConsumableId = 'consumable';
// const List<String> _kProductIds = <String>[
//   _kConsumableId,
//   'upgrade',
//   'subscription'
// ];

class Payment {
  /// Product items to sell to users.
  // RxList products = [].obs;

  List products = [];
  Set<String> productIds = {};
  BehaviorSubject productStream = BehaviorSubject.seeded([]);

  /// TODO This event will be fired when there is incoming purchase.
  PublishSubject purchase;

  InAppPurchaseConnection instance = InAppPurchaseConnection.instance;

  init({@required Set<String> productIds}) {
    // print('Payment::init');
    this.productIds = productIds;
    _initIncomingPurchaseStream();
    _initPayment();
    _pastPurchases();
  }

  /// Subscribe to any incoming purchases at app initialization. These can
  /// propagate from either storefront so it's important to listen as soon as
  /// possible to avoid losing events.
  _initIncomingPurchaseStream() {
    final Stream purchaseUpdates =
        InAppPurchaseConnection.instance.purchaseUpdatedStream;

    /// Listen to any incoming purchases AND any pending purchase from previous app session.
    /// * For instance, app crashed right after purchase and the purchase has not yet delivered,
    /// * Then, the purchase will be notified here with `PurchaseStatus.pending`. This is confirmed on iOS.
    /// No need to unscribe since it is lifetime listener
    ///
    /// ! This is being called only on app start after closing. Hot-Reload or Full-Reload is not working.
    purchaseUpdates.listen((dynamic purchaseDetailsList) {
      print('purchaseUpdates.listen((dynamic purchaseDetailsList) =>');
      purchaseDetailsList.forEach(
        (PurchaseDetails purchaseDetails) async {
          if (purchaseDetails.status == PurchaseStatus.pending) {
            /// Pending purchase from previous app session and new incoming pending purchase will come here.
            // showPendingUI();
            print('PurchaseStatus.pending: Show some pending UI');
            print(purchaseDetails);
            print(purchaseDetails.productID);
            // try {
            //   final re = await InAppPurchaseConnection.instance
            //       .completePurchase(purchaseDetails);
            //   print('purchase completed:');
            //   print(re);
            // } catch (e) {
            //   print('Error on purchase: ');
            //   print(e);
            // }
          } else {
            if (purchaseDetails.status == PurchaseStatus.error) {
              // handleError(purchaseDetails.error);
              print("purchaseDetails.error: ${purchaseDetails.error}");
              // Service.error(purchaseDetails.error);
            } else if (purchaseDetails.status == PurchaseStatus.purchased) {
              print('if (purchaseDetails.status == PurchaseStatus.purchased)');
              bool valid = await _verifyPurchase(purchaseDetails);
              if (valid) {
                deliverProduct(purchaseDetails);
              } else {
                _handleInvalidPurchase(purchaseDetails);
                return;
              }
            }
            if (Platform.isAndroid) {
              if (!_kAutoConsume &&
                  purchaseDetails.productID == _kConsumableId) {
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
      print('done:');
    }, onError: (error) {
      print('error on listening:');
      print(error);
    });
  }

  /// Init the in-app-purchase
  ///
  /// - Check if in-app-purchase is availalbe
  /// - Check if the product ids are available
  ///
  _initPayment() async {

    ///https://github.com/flutter/flutter/issues/53534#issuecomment-674069878
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
    return Future<bool>.value(true);
  }

  /// todo if the purchase is invalid, alert it to users.
  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    // handle invalid purchase here if  _verifyPurchase` failed.
  }

  /// todo connect to Functions and open boxes.
  void deliverProduct(PurchaseDetails purchaseDetails) async {
    // IMPORTANT!! Always verify a purchase purchase details before delivering the product.
    if (purchaseDetails.productID == _kConsumableId) {
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

  _pastPurchases() async {
    final QueryPurchaseDetailsResponse response =
        await InAppPurchaseConnection.instance.queryPastPurchases();
    if (response.error != null) {
      // Handle the error.
      print('error: response.error:');
      print(response.error);
    }
    print('reponse:');
    print(response.pastPurchases);
    for (PurchaseDetails purchase in response.pastPurchases) {
      print('previous purchase:');
      print(purchase);
      if (Platform.isIOS) {
        // Mark that you've delivered the purchase. Only the App Store requires
        // this final confirmation.
        InAppPurchaseConnection.instance.completePurchase(purchase);
      }
    }
  }
}
