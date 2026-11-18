package dev.phonelink.phonelink_android

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        PhoneRuntime.attachActivity(this)
        return PhoneRuntime.getEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        PhoneRuntime.detachActivity(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
