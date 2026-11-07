plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// 关于页上的构建编号:当前提交的短哈希;没有 git(如从源码包编译)时写 dev
val gitHash: String = runCatching {
    providers.exec { commandLine("git", "rev-parse", "--short=7", "HEAD") }.standardOutput.asText.get().trim()
}.getOrNull()?.takeIf { it.isNotEmpty() } ?: "dev"

android {
    namespace = "com.wangzan101.mika"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.wangzan101.mika"
        minSdk = 30
        targetSdk = 35
        versionCode = 39
        versionName = "0.1.38"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "GIT_HASH", "\"$gitHash\"")
        // 关于页版本号后的 Beta 标记;出正式版时改成 false
        buildConfigField("boolean", "BETA", "true")
    }

    // 沙箱程序只有 arm64 版本(jniLibs/arm64-v8a);APK 不限 ABI,别的设备照常安装、显示「此设备不支持沙箱」。
    // 沙箱程序要从 nativeLibraryDir 直接执行,安装时必须解到磁盘
    packaging { jniLibs { useLegacyPackaging = true } }

    // 发布用的包(perf、release)按架构再出一份:除了全架构包,另出只带 arm64-v8a 原生库的小包。
    // 两个包代码、资源、版本号、签名都一样,只差 lib/ 下的其他架构;各自是完整 APK,不是一起安装的拆分包。
    // 产物:app-universal-<类型>.apk、app-arm64-v8a-<类型>.apk。拆分对所有构建类型生效,
    // 所以只在这次构建要出 perf/release 包时打开,单独构建调试包时产物仍是 app-debug.apk。
    splits {
        abi {
            isEnable = gradle.startParameter.taskNames.any { Regex("(?i)(perf|release)").containsMatchIn(it) }
            reset()
            include("arm64-v8a")
            isUniversalApk = true
        }
    }
    // 自带的运行环境(assets/runtime/rootfs.tar.xz,tools/sandbox/build-runtime.py 生成)已是 xz,不再压一遍
    androidResources { noCompress += "xz" }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 评测任务集(仓库根目录 eval/tasks)打进测试包的 assets,真机评测跑器从那里读题
    sourceSets.getByName("androidTest").assets.srcDir(rootProject.file("eval/tasks"))

    buildTypes {
        // 真机验收时并排安装,保留发行版和用户数据;默认构建标识不变。
        if (providers.gradleProperty("devInstall").isPresent) getByName("debug") {
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Mika Dev")
        }
        // 看流畅度用的包:和发布版一样不可调试(调试包不做预先编译,界面慢好几倍,手感不作数),
        // 用本机调试签名,能直接覆盖调试包、保留数据;可被性能工具采样。./gradlew :app:assemblePerf
        create("perf") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            isProfileable = true
            matchingFallbacks += "release"
        }
    }

    buildFeatures {
        compose = true
        aidl = true
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core"))
    implementation(libs.protobuf.lite)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.webkit)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.xz)
    implementation(libs.commonmark)
    implementation(libs.commonmark.ext.gfm.tables)
    implementation(libs.commonmark.ext.gfm.strikethrough)
    // 两种识别模型都随 APK 安装；首次使用不依赖 Play 服务下载。
    implementation(libs.mlkit.text.recognition)
    implementation(libs.mlkit.text.recognition.chinese)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    // 沙箱路径契约(core 的 testFixtures):AndroidSandbox 在 JVM 与真机上都跑同一套
    testImplementation(testFixtures(project(":core")))
    androidTestImplementation(testFixtures(project(":core")))

    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.okhttp.mockwebserver)
    androidTestImplementation(libs.junit)
}

// LicensesTest 读仓库的 licenses/THIRD_PARTY_NOTICES.md:让它参与测试的增量判断
tasks.withType<Test>().configureEach {
    inputs.file(rootProject.file("licenses/THIRD_PARTY_NOTICES.md")).withPropertyName("thirdPartyNotices")
}

// WOOWTECH fork: 品牌层(flavor、品牌字串、签名),见 app/brand.gradle.kts 与 docs-woowtech/FORK.md
apply(from = "brand.gradle.kts")
val woowtechRevision = extra["woowtechRevision"] as Int
val woowtechBrandRes = extra["woowtechBrandRes"] as java.io.File
val woowtechSigning = extra["woowtechSigning"] as java.util.Properties?
android {
    // upstream:上游原样,单测与金样的基准;woowtech:发行用的渥屋助理
    flavorDimensions += "brand"
    productFlavors {
        create("upstream") {
            dimension = "brand"
            isDefault = true
        }
        create("woowtech") {
            dimension = "brand"
            applicationId = "io.woowtech.agent"
            versionCode = (defaultConfig.versionCode ?: 0) * 100 + woowtechRevision
            versionName = "${defaultConfig.versionName}-woow.$woowtechRevision"
            // 只出有正式文案的语言(和 brand.properties 的 ui.languages、res/xml/locales_config.xml 一致)。
            // zh-rTW 不是另一种界面语言:AndroidX、Material、Play 服务的繁体译文在 values-zh-rTW,只留 b+zh+Hant 会滤掉它们,
            // 读屏在繁体界面念英文(Close navigation menu)。香港、澳门的手机也用这份;zh-rHK 不收,Compose UI 那份是粤语口语(「閂」「揀咗」)。
            // Compose UI 的 zh-rTW 也有 state_on/state_off:系统语言是 zh-TW 时这两句用它的「已開啟」「已關閉」,和上游一样。
            // aapt2 留 zh-rTW 时会连带留下上游简体的 values-zh,所以 woowtech 变体另外传 --exclude-configs zh(文件末尾的 onVariants)。
            resourceConfigurations += listOf("en", "b+zh+Hant", "zh-rTW")
        }
    }
    sourceSets.getByName("woowtech").res.srcDir(woowtechBrandRes)
    if (woowtechSigning != null) {
        productFlavors.getByName("woowtech").signingConfig = signingConfigs.create("woowtech") {
            storeFile = file(woowtechSigning.getProperty("storeFile"))
            storePassword = woowtechSigning.getProperty("storePassword")
            keyAlias = woowtechSigning.getProperty("keyAlias")
            keyPassword = woowtechSigning.getProperty("keyPassword")
        }
    }
}
androidComponents {
    // 上游的单测、金样、仪器测试按 Mika 的品牌和包名写:只在 upstream 上跑
    beforeVariants { variant ->
        if (variant.flavorName == "woowtech") {
            variant.enableUnitTest = false
            variant.androidTest.enable = false
        }
    }
    // WOOWTECH fork: -c 里有 zh-rTW 时,aapt2 连它的上层 values-zh(上游的简体界面,没换品牌名)也留下,woowtech 变体排除它。
    // --exclude-configs zh 只去掉语言正好是 zh 的值(含 zh-night、zh-v26),b+zh+Hant、zh-rTW 不受影响
    onVariants { variant ->
        if (variant.flavorName == "woowtech") {
            variant.androidResources.aaptAdditionalParameters.addAll("--exclude-configs", "zh")
        }
    }
}
