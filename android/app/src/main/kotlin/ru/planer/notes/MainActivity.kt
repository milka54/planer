package ru.planer.notes

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Native 3-min chain for background notifications (see BgCheckReceiver.kt).
        BgScheduler.scheduleNext(applicationContext)
    }
}
