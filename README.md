# In app purchase module for Fireflutter

In app purchase for fireflutter

# Setup

- Create an instance of `Payment` class some where in global space.

```dart
final Payment payment = Payment();
```

- Let the in-app-purchase plugin know that we are using it.

```dart
import 'package:in_app_purchase/in_app_purchase.dart';
void main() {
  // Let the plugin know that this app supports pending purchases.
  InAppPurchaseConnection.enablePendingPurchases();
  runApp(MyApp());
}
```

- Inititiate `Payment` instance with productIds of App/Play store.

```dart
class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    payment.init(productIds: {'product1', 'product2', 'lucky_box'});
    super.initState();
  }
```
