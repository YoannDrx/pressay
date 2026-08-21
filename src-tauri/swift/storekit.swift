import Dispatch
import Foundation
import StoreKit

private typealias ResponsePointer = UnsafeMutablePointer<PressayStoreKitResponse>

private struct ProductPayload: Codable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

private struct TransactionPayload: Codable {
    let status: String
    let productId: String?
    let transactionId: String?
    let signedTransaction: String?
}

private struct EntitlementsPayload: Codable {
    let transactions: [TransactionPayload]
}

private final class ResultBox: @unchecked Sendable {
    var payload: String?
    var error: String?
}

private func duplicateCString(_ text: String) -> UnsafeMutablePointer<CChar>? {
    text.withCString { strdup($0) }
}

private func makeResponse() -> ResponsePointer {
    let response = ResponsePointer.allocate(capacity: 1)
    response.initialize(
        to: PressayStoreKitResponse(payload: nil, success: 0, error_message: nil)
    )
    return response
}

private func encode<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "app.pressay.storekit", code: 1)
    }
    return string
}

private func publicErrorCode(_ error: Error) -> String {
    let error = error as NSError
    if error.domain.hasPrefix("storekit_") {
        return error.domain
    }
    return "storekit_operation_failed"
}

private func decodeProductIds(_ pointer: UnsafePointer<CChar>) throws -> [String] {
    let data = Data(String(cString: pointer).utf8)
    let values = try JSONDecoder().decode([String].self, from: data)
    guard !values.isEmpty, values.count <= 8, values.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) else {
        throw NSError(domain: "app.pressay.storekit", code: 2)
    }
    return values
}

private func runStoreKitOperation(
    _ operation: @escaping @Sendable () async throws -> String
) -> ResponsePointer {
    let response = makeResponse()
    guard #available(macOS 12.0, *) else {
        response.pointee.error_message = duplicateCString("storekit_unavailable")
        return response
    }

    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached(priority: .userInitiated) {
        defer { semaphore.signal() }
        do {
            box.payload = try await operation()
        } catch {
            // StoreKit/NSError descriptions are intentionally not returned or
            // logged because provider messages may contain account context.
            box.error = publicErrorCode(error)
        }
    }
    semaphore.wait()

    if let payload = box.payload {
        response.pointee.payload = duplicateCString(payload)
        response.pointee.success = 1
    } else {
        response.pointee.error_message = duplicateCString(box.error ?? "storekit_unknown_error")
    }
    return response
}

@_cdecl("pressay_storekit_products")
public func storeKitProducts(
    _ productIdsJson: UnsafePointer<CChar>
) -> UnsafeMutablePointer<PressayStoreKitResponse> {
    let ids: [String]
    do {
        ids = try decodeProductIds(productIdsJson)
    } catch {
        let response = makeResponse()
        response.pointee.error_message = duplicateCString("storekit_products_invalid")
        return response
    }
    return runStoreKitOperation {
        let products = try await Product.products(for: ids)
        let payload = products
            .map {
                ProductPayload(
                    id: $0.id,
                    displayName: $0.displayName,
                    description: $0.description,
                    displayPrice: $0.displayPrice
                )
            }
            .sorted { $0.id < $1.id }
        return try encode(payload)
    }
}

@_cdecl("pressay_storekit_purchase")
public func storeKitPurchase(
    _ productIdPointer: UnsafePointer<CChar>,
    _ accountTokenPointer: UnsafePointer<CChar>
) -> UnsafeMutablePointer<PressayStoreKitResponse> {
    let productId = String(cString: productIdPointer)
    guard let accountToken = UUID(uuidString: String(cString: accountTokenPointer)) else {
        let response = makeResponse()
        response.pointee.error_message = duplicateCString("storekit_account_invalid")
        return response
    }
    return runStoreKitOperation {
        guard let product = try await Product.products(for: [productId]).first else {
            throw NSError(domain: "storekit_product_unavailable", code: 1)
        }
        let result = try await product.purchase(options: [.appAccountToken(accountToken)])
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                return try encode(
                    TransactionPayload(
                        status: "purchased",
                        productId: transaction.productID,
                        transactionId: String(transaction.id),
                        signedTransaction: verification.jwsRepresentation
                    )
                )
            case .unverified:
                return try encode(
                    TransactionPayload(
                        status: "unverified",
                        productId: productId,
                        transactionId: nil,
                        signedTransaction: nil
                    )
                )
            }
        case .pending:
            return try encode(
                TransactionPayload(
                    status: "pending",
                    productId: productId,
                    transactionId: nil,
                    signedTransaction: nil
                )
            )
        case .userCancelled:
            return try encode(
                TransactionPayload(
                    status: "cancelled",
                    productId: productId,
                    transactionId: nil,
                    signedTransaction: nil
                )
            )
        @unknown default:
            throw NSError(domain: "storekit_result_unknown", code: 1)
        }
    }
}

@_cdecl("pressay_storekit_current_entitlements")
public func storeKitCurrentEntitlements(
    _ productIdsJson: UnsafePointer<CChar>,
    _ forceSync: Int32
) -> UnsafeMutablePointer<PressayStoreKitResponse> {
    let ids: [String]
    do {
        ids = try decodeProductIds(productIdsJson)
    } catch {
        let response = makeResponse()
        response.pointee.error_message = duplicateCString("storekit_products_invalid")
        return response
    }
    return runStoreKitOperation {
        if forceSync == 1 {
            // Apple requires this prompt to be initiated by an explicit Restore action.
            try await AppStore.sync()
        }
        var transactions: [TransactionPayload] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, ids.contains(transaction.productID) else {
                continue
            }
            transactions.append(
                TransactionPayload(
                    status: "purchased",
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    signedTransaction: result.jwsRepresentation
                )
            )
        }
        return try encode(EntitlementsPayload(transactions: transactions))
    }
}

@_cdecl("pressay_storekit_finish_transaction")
public func storeKitFinishTransaction(
    _ transactionIdPointer: UnsafePointer<CChar>
) -> UnsafeMutablePointer<PressayStoreKitResponse> {
    let transactionIdString = String(cString: transactionIdPointer)
    guard let transactionId = UInt64(transactionIdString) else {
        let response = makeResponse()
        response.pointee.error_message = duplicateCString("storekit_transaction_invalid")
        return response
    }
    return runStoreKitOperation {
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.id == transactionId else {
                continue
            }
            await transaction.finish()
            return "{}"
        }
        throw NSError(domain: "storekit_transaction_not_found", code: 1)
    }
}

@_cdecl("pressay_storekit_free_response")
public func freeStoreKitResponse(
    _ response: UnsafeMutablePointer<PressayStoreKitResponse>?
) {
    guard let response else { return }
    if let payload = response.pointee.payload {
        free(payload)
    }
    if let error = response.pointee.error_message {
        free(error)
    }
    response.deallocate()
}
