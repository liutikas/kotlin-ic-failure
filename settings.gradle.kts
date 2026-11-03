pluginManagement {
    val offlineRepo = providers.gradleProperty("offlineRepo").orNull
    val kotlinVersion = providers.gradleProperty("kotlinVersion").getOrElse("2.4.21")
    repositories {
        if (offlineRepo != null) {
            maven { url = uri(offlineRepo) }
        } else {
            gradlePluginPortal()
            mavenCentral()
        }
    }
    plugins {
        id("org.jetbrains.kotlin.jvm") version kotlinVersion
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    val offlineRepo = providers.gradleProperty("offlineRepo").orNull
    repositories {
        if (offlineRepo != null) {
            maven { url = uri(offlineRepo) }
        } else {
            mavenCentral()
        }
    }
}

rootProject.name = "kt-84271-repro"
include(":lib")
include(":app")
