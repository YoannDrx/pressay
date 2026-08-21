use serde::{Deserialize, Serialize};
use specta::Type;

pub const MONTHLY_PRODUCT_ID: &str = "app.pressay.desktop.mas.pro.monthly";
pub const ANNUAL_PRODUCT_ID: &str = "app.pressay.desktop.mas.pro.annual";
pub const PRODUCT_IDS: [&str; 2] = [MONTHLY_PRODUCT_ID, ANNUAL_PRODUCT_ID];

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct StoreKitProduct {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub display_price: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct StoreKitTransaction {
    pub status: String,
    pub product_id: Option<String>,
    pub transaction_id: Option<String>,
    pub signed_transaction: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoreKitEntitlements {
    transactions: Vec<StoreKitTransaction>,
}

pub fn is_known_product(product_id: &str) -> bool {
    PRODUCT_IDS.contains(&product_id)
}

#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
mod native {
    use super::{StoreKitEntitlements, StoreKitProduct, StoreKitTransaction, PRODUCT_IDS};
    use std::ffi::{CStr, CString};
    use std::os::raw::{c_char, c_int};

    #[repr(C)]
    struct PressayStoreKitResponse {
        payload: *mut c_char,
        success: c_int,
        error_message: *mut c_char,
    }

    unsafe extern "C" {
        fn pressay_storekit_products(
            product_ids_json: *const c_char,
        ) -> *mut PressayStoreKitResponse;
        fn pressay_storekit_purchase(
            product_id: *const c_char,
            account_token: *const c_char,
        ) -> *mut PressayStoreKitResponse;
        fn pressay_storekit_current_entitlements(
            product_ids_json: *const c_char,
            force_sync: c_int,
        ) -> *mut PressayStoreKitResponse;
        fn pressay_storekit_finish_transaction(
            transaction_id: *const c_char,
        ) -> *mut PressayStoreKitResponse;
        fn pressay_storekit_free_response(response: *mut PressayStoreKitResponse);
    }

    fn read_response(response: *mut PressayStoreKitResponse) -> Result<String, String> {
        if response.is_null() {
            return Err("storekit_response_invalid".to_string());
        }
        let value = unsafe {
            let response_ref = &*response;
            if response_ref.success == 1 && !response_ref.payload.is_null() {
                Ok(CStr::from_ptr(response_ref.payload)
                    .to_string_lossy()
                    .into_owned())
            } else if !response_ref.error_message.is_null() {
                Err(CStr::from_ptr(response_ref.error_message)
                    .to_string_lossy()
                    .into_owned())
            } else {
                Err("storekit_response_invalid".to_string())
            }
        };
        unsafe { pressay_storekit_free_response(response) };
        value
    }

    fn product_ids_json() -> Result<CString, String> {
        CString::new(
            serde_json::to_string(&PRODUCT_IDS)
                .map_err(|_| "storekit_products_invalid".to_string())?,
        )
        .map_err(|_| "storekit_products_invalid".to_string())
    }

    pub fn products() -> Result<Vec<StoreKitProduct>, String> {
        let ids = product_ids_json()?;
        let response = unsafe { pressay_storekit_products(ids.as_ptr()) };
        let payload = read_response(response)?;
        serde_json::from_str(&payload).map_err(|_| "storekit_response_invalid".to_string())
    }

    pub fn purchase(product_id: &str, account_token: &str) -> Result<StoreKitTransaction, String> {
        let product_id =
            CString::new(product_id).map_err(|_| "storekit_product_invalid".to_string())?;
        let account_token =
            CString::new(account_token).map_err(|_| "storekit_account_invalid".to_string())?;
        let response =
            unsafe { pressay_storekit_purchase(product_id.as_ptr(), account_token.as_ptr()) };
        let payload = read_response(response)?;
        serde_json::from_str(&payload).map_err(|_| "storekit_response_invalid".to_string())
    }

    pub fn current_entitlements(force_sync: bool) -> Result<Vec<StoreKitTransaction>, String> {
        let ids = product_ids_json()?;
        let response =
            unsafe { pressay_storekit_current_entitlements(ids.as_ptr(), i32::from(force_sync)) };
        let payload = read_response(response)?;
        serde_json::from_str::<StoreKitEntitlements>(&payload)
            .map(|value| value.transactions)
            .map_err(|_| "storekit_response_invalid".to_string())
    }

    pub fn finish(transaction_id: &str) -> Result<(), String> {
        let transaction_id =
            CString::new(transaction_id).map_err(|_| "storekit_transaction_invalid".to_string())?;
        let response = unsafe { pressay_storekit_finish_transaction(transaction_id.as_ptr()) };
        read_response(response).map(|_| ())
    }
}

#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
pub use native::{current_entitlements, finish, products, purchase};

#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
pub fn products() -> Result<Vec<StoreKitProduct>, String> {
    Err("storekit_unavailable".to_string())
}

#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
pub fn purchase(_product_id: &str, _account_token: &str) -> Result<StoreKitTransaction, String> {
    Err("storekit_unavailable".to_string())
}

#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
pub fn current_entitlements(_force_sync: bool) -> Result<Vec<StoreKitTransaction>, String> {
    Err("storekit_unavailable".to_string())
}

#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
pub fn finish(_transaction_id: &str) -> Result<(), String> {
    Err("storekit_unavailable".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalogue_is_closed_to_known_subscription_ids() {
        assert!(is_known_product(MONTHLY_PRODUCT_ID));
        assert!(is_known_product(ANNUAL_PRODUCT_ID));
        assert!(!is_known_product("app.routinekids.family"));
    }
}
