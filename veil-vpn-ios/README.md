# Veil VPN — iOS

Version iOS (SwiftUI + WKWebView) de Veil VPN, identique à la version Android :
- même interface (`VeilVPN/Resources/index.html`)
- actualisation des proxys (spys.me, TheSpeedX, monosans) avec test HTTPS réel + géolocalisation, 1 meilleur proxy par pays
- navigateur intégré dont tout le trafic passe par le proxy choisi

**iOS 17 minimum** (API `WKWebsiteDataStore.proxyConfigurations`).

## Obtenir l'IPA
1. Poussez ce dépôt sur GitHub (branche `main`).
2. Onglet **Actions** → « Build Veil VPN IPA » (ou lancez-le à la main via *Run workflow*).
3. Téléchargez l'artefact **Veil-VPN-ipa** → `Veil-VPN.ipa`.

L'IPA est **non signée** : installez-la avec Sideloadly, AltStore, TrollStore, etc.
