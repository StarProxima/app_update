package sk.fourq.otaupdate;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;
import android.util.Log;

public class InstallResultReceiver extends BroadcastReceiver {

    public static final String ACTION_INSTALL_COMPLETE = "ACTION_INSTALL_COMPLETE";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(OtaUpdatePlugin.TAG, "InstallResultReceiver received ping");
        int status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE
        );

        Log.d(OtaUpdatePlugin.TAG, "Status: "+status);
        String msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent confirmationIntent = null;
            confirmationIntent = getConfirmationIntent(intent);
            if (confirmationIntent != null) {
                context.startActivity(confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            }
            return;
        }
        OtaUpdatePlugin instance = OtaUpdatePlugin.getInstance();
        if (instance != null) {
            if (status == PackageInstaller.STATUS_SUCCESS) {
                instance.onInstallSuccess(msg);
            } else {
                instance.onInstallFailure(msg);
            }
        }
    }

    @SuppressWarnings("deprecation")
    private Intent getConfirmationIntent(Intent intent) {
        Intent confirmationIntent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            confirmationIntent = intent.getExtras().getParcelable(Intent.EXTRA_INTENT, Intent.class);
        } else {
            confirmationIntent = intent.getExtras().getParcelable(Intent.EXTRA_INTENT);
        }
        return confirmationIntent;
    }
}

package sk.fourq.otaupdate;

import android.content.pm.PackageInstaller;
import android.util.Log;

public class InstallSessionCallback extends PackageInstaller.SessionCallback {

    @Override
    public void onActiveChanged(int sessionId, boolean active) {

    }

    @Override
    public void onBadgingChanged(int sessionId) {

    }

    @Override
    public void onCreated(int sessionId) {

    }

    @Override
    public void onFinished(int sessionId, boolean success) {
        Log.d(OtaUpdatePlugin.TAG, "Install session finished " + success);
        // DOES NOT PROPAGATE TO PLUGIN AS IT SHOULD BE HANDLED BY InstallResultReceiver
    }

    @Override
    public void onProgressChanged(int sessionId, float progress) {
        Log.d(OtaUpdatePlugin.TAG, "Install session callback progress " + progress);
        OtaUpdatePlugin otaUpdatePlugin = OtaUpdatePlugin.getInstance();
        if(otaUpdatePlugin != null){
            otaUpdatePlugin.onInstallProgress(progress);
        }
    }
}