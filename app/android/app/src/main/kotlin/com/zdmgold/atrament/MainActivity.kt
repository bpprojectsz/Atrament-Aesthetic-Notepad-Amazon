package com.zdmgold.atrament

import com.amazon.device.iap.PurchasingService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val iapHandler = AmazonIapHandler()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Amazon IAP listener is bound to the Application context so it
        // survives Activity recreation. Registering with `this` (Activity)
        // doubles the registration on configuration change, which the
        // Appstore SDK rejects. SDK 3.0.4 is pinned in build.gradle —
        // later versions throw "Resource already registered" here.
        PurchasingService.registerListener(applicationContext, iapHandler)
        iapHandler.attach(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "amazon_iap"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> result.success(null)
                "getUserData" -> {
                    PurchasingService.getUserData()
                    result.success(null)
                }
                "getProductData" -> {
                    @Suppress("UNCHECKED_CAST")
                    val skus = (call.argument<List<String>>("skus") ?: emptyList()).toSet()
                    PurchasingService.getProductData(skus)
                    result.success(null)
                }
                "purchase" -> {
                    val sku = call.argument<String>("sku")
                    if (sku == null) {
                        result.error("INVALID_SKU", "sku argument is required", null)
                    } else {
                        PurchasingService.purchase(sku)
                        result.success(null)
                    }
                }
                "getPurchaseUpdates" -> {
                    val reset = call.argument<Boolean>("reset") ?: false
                    PurchasingService.getPurchaseUpdates(reset)
                    result.success(null)
                }
                "notifyFulfillment" -> {
                    val receiptId = call.argument<String>("receiptId")
                    val tag = call.argument<String>("result") ?: "FULFILLED"
                    val outcome = if (tag == "FULFILLED") {
                        com.amazon.device.iap.model.FulfillmentResult.FULFILLED
                    } else {
                        com.amazon.device.iap.model.FulfillmentResult.UNAVAILABLE
                    }
                    if (receiptId != null) {
                        PurchasingService.notifyFulfillment(receiptId, outcome)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
