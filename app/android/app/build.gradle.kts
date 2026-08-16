plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.agrobarter.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.agrobarter.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ATENÇÃO — assinatura de release pendente. Ver docs/RELEASE.md (item 1).
            //
            // A keystore de debug não é secreta: senha conhecida e a MESMA em
            // toda máquina. Enquanto o release for assinado com ela, qualquer
            // um consegue produzir um "agroBarter atualizado" que o aparelho de
            // um testador aceita instalar por cima do legítimo — e o
            // distribute.yml entrega este APK aos testadores a cada push
            // aprovado na main. É também bloqueio duro para a Play Store.
            //
            // Mantido como está de propósito, até o release entrar na pauta:
            // trocar isto exige decidir de quem é a conta da loja e onde a
            // chave fica guardada, e uma chave de release perdida não se
            // recupera.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
