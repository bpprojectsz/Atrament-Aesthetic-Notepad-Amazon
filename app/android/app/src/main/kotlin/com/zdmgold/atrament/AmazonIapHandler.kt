package com.zdmgold.atrament

import com.amazon.device.iap.PurchasingListener
import com.amazon.device.iap.model.ProductDataResponse
import com.amazon.device.iap.model.PurchaseResponse
import com.amazon.device.iap.model.PurchaseUpdatesResponse
import com.amazon.device.iap.model.UserDataResponse
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Forwards Amazon Appstore SDK callbacks to Dart over a MethodChannel
/// named `amazon_iap_events`. One instance is created per activity in
/// MainActivity.configureFlutterEngine and registered once via
/// PurchasingService.registerListener.
class AmazonIapHandler : PurchasingListener {
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "amazon_iap_events")
    }

    override fun onUserDataResponse(response: UserDataResponse) {
        // Not consumed by the app. The SKU and marketplace are not
        // surfaced to the user; the purchase status comes through
        // onPurchaseResponse and onPurchaseUpdatesResponse only.
    }

    override fun onProductDataResponse(response: ProductDataResponse) {
        val data = response.productData ?: emptyMap()
        val products = data.values.map { p ->
            mapOf(
                "sku" to p.sku,
                "price" to p.price,
                "title" to p.title,
                "description" to p.description
            )
        }
        channel?.invokeMethod("onProductData", products)
    }

    override fun onPurchaseResponse(response: PurchaseResponse) {
        val receipt = response.receipt
        val event = mapOf(
            "status" to response.requestStatus.name,
            "receiptId" to (receipt?.receiptId ?: ""),
            "sku" to (receipt?.sku ?: "")
        )
        channel?.invokeMethod("onPurchaseResponse", event)
    }

    override fun onPurchaseUpdatesResponse(response: PurchaseUpdatesResponse) {
        val receipts = response.receipts ?: emptyList()
        val events = receipts.map { r ->
            mapOf(
                "status" to "RESTORED",
                "receiptId" to r.receiptId,
                "sku" to r.sku
            )
        }
        channel?.invokeMethod("onPurchaseUpdatesResponse", events)
    }
}
