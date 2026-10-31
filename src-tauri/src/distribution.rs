//! Compile-time distribution channel and the outbound pages each channel may
//! open. The Mac App Store build must not expose self-update UI (App Review
//! 2.4.5) nor any external purchase link (3.1.1), so those URLs only exist in
//! the binaries that are allowed to use them.

use serde::{Deserialize, Serialize};
use specta::Type;
use tauri::AppHandle;
use tauri_plugin_opener::OpenerExt;

use crate::settings::get_settings;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum DistributionChannel {
    MacAppStore,
    Direct,
    /// Unbundled development or inherited non-macOS builds.
    Development,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Type)]
#[serde(rename_all = "camelCase")]
pub struct DistributionInfo {
    pub channel: DistributionChannel,
    /// True only when the self-updater plugin is compiled in.
    pub updater_available: bool,
}

pub const fn distribution_channel() -> DistributionChannel {
    if cfg!(feature = "mas") {
        DistributionChannel::MacAppStore
    } else if cfg!(feature = "direct") {
        DistributionChannel::Direct
    } else {
        DistributionChannel::Development
    }
}

pub const fn updater_available() -> bool {
    cfg!(feature = "updater")
}

pub fn distribution_info() -> DistributionInfo {
    DistributionInfo {
        channel: distribution_channel(),
        updater_available: updater_available(),
    }
}

#[tauri::command]
#[specta::specta]
pub fn get_distribution_info() -> DistributionInfo {
    distribution_info()
}

/// Pages the UI may open. The URL is chosen here, per channel, so the web
/// bundle (shared by every channel) never carries a purchase link.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Type)]
#[serde(rename_all = "snake_case")]
pub enum ExternalPage {
    Support,
    Terms,
    Privacy,
    /// App Store subscriptions on MAS, the web billing portal on Direct.
    ManageSubscription,
    /// Web checkout; only exists in the Direct channel.
    DirectCheckout,
    /// Apple's subscription settings, whatever the channel: an App Store
    /// subscription keeps billing after account deletion until cancelled there.
    AppleSubscriptions,
}

const SITE_ORIGIN: &str = "https://press-say.app";
const APP_STORE_SUBSCRIPTIONS_URL: &str = "https://apps.apple.com/account/subscriptions";
#[cfg(feature = "direct")]
const DIRECT_BILLING_URL: &str = "https://press-say.app/account/billing";

/// The web legal and support routes exist only in French and English, the
/// two reviewed app languages.
fn site_locale(app_language: &str) -> &'static str {
    crate::settings::reviewed_app_language(app_language)
}

pub fn external_page_url(page: ExternalPage, app_language: &str) -> Result<String, String> {
    let locale = site_locale(app_language);
    match page {
        ExternalPage::Support => Ok(format!("{SITE_ORIGIN}/{locale}/support")),
        ExternalPage::Terms => Ok(format!("{SITE_ORIGIN}/{locale}/terms")),
        ExternalPage::Privacy => Ok(format!("{SITE_ORIGIN}/{locale}/privacy")),
        ExternalPage::ManageSubscription => manage_subscription_url(),
        ExternalPage::DirectCheckout => direct_checkout_url(locale),
        ExternalPage::AppleSubscriptions => Ok(APP_STORE_SUBSCRIPTIONS_URL.to_string()),
    }
}

#[cfg(feature = "direct")]
fn manage_subscription_url() -> Result<String, String> {
    Ok(DIRECT_BILLING_URL.to_string())
}

#[cfg(not(feature = "direct"))]
fn manage_subscription_url() -> Result<String, String> {
    Ok(APP_STORE_SUBSCRIPTIONS_URL.to_string())
}

/// Direct builds sell through the web checkout. The checkout itself collects
/// consent, runs Stripe and grants Pro through a signed webhook; the app only
/// opens the page and refreshes its entitlement when the user comes back.
///
/// The page is opened through the site's sign-in route, with the localized
/// pricing page as its destination. A browser that is already signed in (the
/// app's own OAuth sign-in runs in it) is redirected straight to pricing;
/// otherwise the site asks for the account first and then returns to pricing,
/// so the Checkout is always bound to a Pressay account. No account
/// identifier ever goes into the URL.
///
/// Only `stripe-purchases` builds carry this URL. That feature implies
/// `direct`, which `lib.rs` refuses to combine with `mas`: the Mac App Store
/// binary cannot contain a link to an external purchase (App Review 3.1.1).
#[cfg(feature = "stripe-purchases")]
fn direct_checkout_url(locale: &str) -> Result<String, String> {
    let pricing = format!("/{locale}/{DIRECT_PRICING_PATH}");
    let mut url = url::Url::parse(&format!("{SITE_ORIGIN}/sign-in"))
        .map_err(|_| "direct_checkout_unavailable".to_string())?;
    url.query_pairs_mut()
        .append_pair("locale", locale)
        .append_pair("redirect_url", &pricing);
    Ok(url.into())
}

/// The App Store release workflow greps the Store binary for this literal.
#[cfg(feature = "stripe-purchases")]
const DIRECT_PRICING_PATH: &str = "pricing?source=pressay-desktop";

#[cfg(not(feature = "stripe-purchases"))]
fn direct_checkout_url(_locale: &str) -> Result<String, String> {
    Err("direct_checkout_unavailable".to_string())
}

#[tauri::command]
#[specta::specta]
pub fn open_external_page(app: AppHandle, page: ExternalPage) -> Result<(), String> {
    if page == ExternalPage::DirectCheckout {
        // Same backend gate as the UI: closed until the Stripe matrix passes.
        let capabilities = crate::capabilities::Capabilities::local_free();
        if capabilities.direct_checkout != crate::capabilities::CapabilityAccess::Enabled {
            return Err("capability_release_gate:direct_checkout".to_string());
        }
    }
    let url = external_page_url(page, &get_settings(&app).app_language)?;
    app.opener()
        .open_url(url, None::<String>)
        .map_err(|_| "external_page_open_failed".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_test_build_is_not_a_store_or_updater_build() {
        let info = distribution_info();
        assert_eq!(info.updater_available, cfg!(feature = "updater"));
        if cfg!(feature = "mas") {
            assert_eq!(info.channel, DistributionChannel::MacAppStore);
            assert!(!info.updater_available);
        }
    }

    #[test]
    fn legal_pages_follow_the_two_reviewed_site_locales() {
        assert_eq!(
            external_page_url(ExternalPage::Terms, "fr-FR").unwrap(),
            "https://press-say.app/fr/terms"
        );
        assert_eq!(
            external_page_url(ExternalPage::Privacy, "de").unwrap(),
            "https://press-say.app/en/privacy"
        );
        assert_eq!(
            external_page_url(ExternalPage::Support, "fr").unwrap(),
            "https://press-say.app/fr/support"
        );
    }

    #[test]
    fn purchase_links_follow_the_channel() {
        let manage = external_page_url(ExternalPage::ManageSubscription, "en").unwrap();
        if cfg!(feature = "direct") {
            assert_eq!(manage, "https://press-say.app/account/billing");
        } else {
            assert_eq!(manage, "https://apps.apple.com/account/subscriptions");
        }
        assert_eq!(
            external_page_url(ExternalPage::AppleSubscriptions, "fr").unwrap(),
            "https://apps.apple.com/account/subscriptions"
        );
    }

    #[test]
    fn checkout_exists_only_in_stripe_purchase_builds() {
        let checkout = external_page_url(ExternalPage::DirectCheckout, "fr-FR");
        if cfg!(feature = "stripe-purchases") {
            let url = url::Url::parse(&checkout.unwrap()).unwrap();
            assert_eq!(url.origin().ascii_serialization(), "https://press-say.app");
            assert_eq!(url.path(), "/sign-in");
            let query: Vec<(String, String)> = url.query_pairs().into_owned().collect();
            assert_eq!(
                query,
                [
                    ("locale".to_string(), "fr".to_string()),
                    (
                        "redirect_url".to_string(),
                        "/fr/pricing?source=pressay-desktop".to_string()
                    ),
                ]
            );
        } else {
            assert_eq!(checkout.unwrap_err(), "direct_checkout_unavailable");
        }
    }

    /// App Review 3.1.1: no page the Store build can open leads to a web
    /// purchase. Runs in CI with `--features mas` and `storekit-purchases`.
    #[test]
    fn app_store_build_opens_no_external_purchase_page() {
        if !cfg!(feature = "mas") {
            return;
        }
        assert_eq!(distribution_channel(), DistributionChannel::MacAppStore);
        for page in [
            ExternalPage::Support,
            ExternalPage::Terms,
            ExternalPage::Privacy,
            ExternalPage::ManageSubscription,
            ExternalPage::DirectCheckout,
            ExternalPage::AppleSubscriptions,
        ] {
            for language in ["en", "fr"] {
                if let Ok(url) = external_page_url(page, language) {
                    assert!(!url.contains("pricing"), "{url}");
                    assert!(!url.contains("checkout"), "{url}");
                    assert!(!url.contains("press-say.app/account"), "{url}");
                    assert!(!url.contains("sign-in"), "{url}");
                }
            }
        }
        assert_eq!(
            external_page_url(ExternalPage::DirectCheckout, "en").unwrap_err(),
            "direct_checkout_unavailable"
        );
    }
}
