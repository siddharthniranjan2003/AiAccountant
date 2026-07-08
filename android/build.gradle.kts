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
subprojects {
    project.evaluationDependsOn(":app")
}

// Kotlin incremental compilation fails on Windows when the pub cache (C:) and
// project build dir (D:) are on different drives — relative path resolution breaks.
subprojects {
    val isSentryFlutter = name == "sentry_flutter"
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        incremental = false
        // sentry_flutter 8.14.2 pins Kotlin languageVersion 1.6, which this
        // project's Kotlin 2.2 compiler rejects ("1.6 is no longer supported").
        // Raise just that module to a supported version (its code is 1.6-era, so
        // 1.8 compiles fine). Remove if sentry_flutter is upgraded to 9.x.
        if (isSentryFlutter) {
            compilerOptions {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
