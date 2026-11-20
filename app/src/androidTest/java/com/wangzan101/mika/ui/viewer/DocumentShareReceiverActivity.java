package com.wangzan101.mika.ui.viewer;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/** Separate test-APK process: reads only the URI granted by the real system share flow. */
public class DocumentShareReceiverActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        Intent result = new Intent("document.test.SHARE_RECEIVED");
        // Test APK application ID is target application ID + .test.
        String target = getPackageName().replaceFirst("\\.test$", "");
        result.setPackage(target);
        try {
            Uri uri = getIntent().getParcelableExtra(Intent.EXTRA_STREAM);
            try (InputStream in = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096];
                int size;
                while ((size = in.read(buffer)) != -1) {
                    out.write(buffer, 0, size);
                    if (out.size() > 65536) throw new IllegalArgumentException("Test sample too large");
                }
                result.putExtra("bytes", out.toByteArray());
                result.putExtra("uri", uri.toString());
            }
        } catch (Exception error) { result.putExtra("error", error.toString()); }
        sendBroadcast(result);
        finish();
    }
}
