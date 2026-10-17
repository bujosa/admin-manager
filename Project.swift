import ProjectDescription

let project = Project(
    name: "AdminManager",
    targets: [
        .target(
            name: "AdminManager",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bujosa.adminmanager",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Admin Manager Beta",
                "CFBundleIconName": "AppIcon",
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleGetInfoString": "AdminManager 1.0.0 Beta",
                "AMReleaseChannel": "beta",
                "NSLocalNetworkUsageDescription": "AdminManager connects to the devices you add to display their storage, system metrics and services over your local network.",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "14.0",
                "NSMainStoryboardFile": "",
                "NSPrincipalClass": "NSApplication",
                "LSApplicationCategoryType": "public.app-category.utilities"
            ]),
            sources: ["AdminManager/Sources/**"],
            resources: ["AdminManager/Resources/**"],
            entitlements: .file(path: "AdminManager/AdminManager.entitlements"),
            dependencies: []
        )
    ]
)
