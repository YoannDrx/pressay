#ifndef pressay_storekit_bridge_h
#define pressay_storekit_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char* payload;
    int success;
    char* error_message;
} PressayStoreKitResponse;

PressayStoreKitResponse* pressay_storekit_products(const char* product_ids_json);
PressayStoreKitResponse* pressay_storekit_purchase(const char* product_id, const char* account_token);
PressayStoreKitResponse* pressay_storekit_current_entitlements(const char* product_ids_json, int force_sync);
PressayStoreKitResponse* pressay_storekit_finish_transaction(const char* transaction_id);
void pressay_storekit_free_response(PressayStoreKitResponse* response);

#ifdef __cplusplus
}
#endif

#endif
