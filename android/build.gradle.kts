allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Raise the compile SDK of plugins that pin an old one.
//
// android_play_install_referrer 0.4.0 — the newest there is, and what reads
// the Play referrer an ambassador link travels on — declares
// `compileSdkVersion 33`. AndroidX has since moved on: androidx.exifinterface
// 1.4.1 and friends refuse to be compiled against anything below 34, and they
// arrive transitively, so this build broke on its own without a line of our
// code changing. Compiling a plugin against a newer SDK does not change what
// it runs on: minSdk and targetSdk are untouched.
//
// It has to be afterEvaluate — a plugins.withId hook fires while the plugin's
// own script is still to come, and that script then sets 33 straight back —
// and it has to be registered before the evaluationDependsOn below, which
// evaluates these projects and would leave nothing left to hook.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current < 35) {
                android.compileSdkVersion(35)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
