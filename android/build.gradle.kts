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
    // file_picker и другие плагины собраны под android-34, зависимости
    // требуют 36 — поднимаем compileSdk всем подпроектам принудительно.
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.api.dsl.CommonExtension) {
            androidExt.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
