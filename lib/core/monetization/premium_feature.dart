enum PremiumFeature {
  projectFolders,
  pdfReports,
  customBranding,
  overlayColors,
  savedTemplates,
  proofVerification,
}

extension PremiumFeatureLabel on PremiumFeature {
  String get accessLabel => switch (this) {
        PremiumFeature.projectFolders => 'project folders',
        PremiumFeature.pdfReports => 'PDF proof reports',
        PremiumFeature.customBranding => 'custom branding',
        PremiumFeature.overlayColors => 'premium overlay colors',
        PremiumFeature.savedTemplates => 'saved note templates',
        PremiumFeature.proofVerification => 'proof verification',
      };
}
