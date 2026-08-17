use tauri::{AppHandle, Manager};
use tauri_plugin_opener::OpenerExt;

use crate::cloud::{
    self, CloudAccountSnapshot, CloudAuthConfig, CloudAuthProvider, CloudAuthRuntime,
};
use crate::settings::get_settings;

fn public_error(error: cloud::CloudFailure) -> String {
    error.code
}

#[tauri::command]
#[specta::specta]
pub async fn get_cloud_auth_config(app: AppHandle) -> Result<CloudAuthConfig, String> {
    cloud::get_auth_config(&get_settings(&app))
        .await
        .map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn request_cloud_magic_link(app: AppHandle, email: String) -> Result<(), String> {
    let runtime = app.state::<CloudAuthRuntime>();
    let state = runtime.begin().map_err(public_error)?;
    if let Err(error) = cloud::request_magic_link(&get_settings(&app), email.trim(), &state).await {
        runtime.clear();
        return Err(public_error(error));
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub async fn begin_cloud_social_login(
    app: AppHandle,
    provider: CloudAuthProvider,
) -> Result<(), String> {
    let runtime = app.state::<CloudAuthRuntime>();
    let state = runtime.begin().map_err(public_error)?;
    let authorization_url =
        match cloud::social_login_url(&get_settings(&app), provider, &state).await {
            Ok(url) => url,
            Err(error) => {
                runtime.clear();
                return Err(public_error(error));
            }
        };
    if app
        .opener()
        .open_url(authorization_url, None::<String>)
        .is_err()
    {
        runtime.clear();
        return Err("cloud_browser_open_failed".to_string());
    }
    Ok(())
}

#[tauri::command]
#[specta::specta]
pub async fn get_cloud_account_snapshot(app: AppHandle) -> Result<CloudAccountSnapshot, String> {
    cloud::account_snapshot(&app).await.map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn disconnect_cloud_account(app: AppHandle) -> Result<(), String> {
    cloud::sign_out(&app).await.map_err(public_error)
}

#[tauri::command]
#[specta::specta]
pub async fn delete_cloud_account(app: AppHandle) -> Result<(), String> {
    cloud::delete_account(&app).await.map_err(public_error)
}
