package com.vuminhduc.vuminhduc_2380614671_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

/**
 * Dịch vụ Trợ Năng (Accessibility Service) chạy ngầm 24/7 trên Android.
 * Ngay cả khi con thoát app hoặc bấm nút Home:
 * Dịch vụ này vẫn tiếp tục bắt sự kiện mở ứng dụng (TYPE_WINDOW_STATE_CHANGED).
 * Nếu con mở ứng dụng nằm trong danh mục Cha Mẹ cấm (TikTok, Facebook, Game online...):
 * Hệ thống sẽ lập tức chặn lại và đá văng về Màn Hình Khóa Bảo Vệ của Gia Đình.
 */
class FamilyAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "FamilyAccessGuard"

        // Danh sách Package name của các ứng dụng thường bị Cha Mẹ cấm
        val BLOCKED_PACKAGES = setOf(
            "com.zhiliaoapp.musically",       // TikTok Quốc Tế
            "com.ss.android.ugc.trill",       // TikTok Châu Á
            "com.facebook.katana",            // Facebook
            "com.facebook.orca",              // Messenger
            "com.roblox.client",              // Roblox
            "com.garena.game.kgvn",           // Liên Quân Mobile
            "com.dts.freefireth",             // Free Fire
            "com.miHoYo.GenshinImpact",       // Genshin Impact
            "com.vng.pubgmobile"              // PUBG Mobile
        )
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return
        }

        val packageName = event.packageName?.toString() ?: return
        Log.d(TAG, "Phát hiện ứng dụng đang mở ở Foreground: $packageName")

        // Kiểm tra xem ứng dụng này có nằm trong danh sách Cha Mẹ cấm hay không
        if (isPackageBlocked(packageName)) {
            Log.w(TAG, "⛔ [CHẶN NGAY] Phát hiện con đang cố mở ứng dụng bị cấm: $packageName")

            // 1. Lập tức đá con văng ra Màn hình chính (Home)
            performGlobalAction(GLOBAL_ACTION_HOME)

            // 2. Hiển thị thông báo cảnh báo tức thì
            Toast.makeText(
                applicationContext,
                "⛔ ỨNG DỤNG BỊ CHẶN BỞI CHA MẸ!\nHệ thống chạy ngầm đã khóa ứng dụng này.",
                Toast.LENGTH_LONG
            ).show()

            // 3. Tự động bật màn hình Khóa Cưỡng Chế của ứng dụng Family Safety lên đè màn hình
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(applicationContext.packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("APP_BLOCKED_TRIGGERED", true)
                    putExtra("BLOCKED_PACKAGE_NAME", packageName)
                }
                if (launchIntent != null) {
                    startActivity(launchIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Không thể mở Activity khóa máy: ${e.message}")
            }
        }
    }

    override fun onInterrupt() {
        Log.i(TAG, "Dịch vụ giám sát trợ năng bị gián đoạn.")
    }

    private fun isPackageBlocked(pkg: String): Boolean {
        return BLOCKED_PACKAGES.any { pkg.equals(it, ignoreCase = true) || pkg.contains(it, ignoreCase = true) }
    }
}
