package android.stnvactllib;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.SocketException;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.List;

import android.app.Activity;
import android.app.ActivityManagerNative;
import android.app.AlarmManager;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.content.res.Configuration;
import android.net.Uri;
import android.os.Process;
import android.os.RecoverySystem;
import android.os.RemoteException;
import android.os.SystemClock;
import android.os.ServiceManager;
import android.os.SystemProperties;
import android.os.UserHandle;
import android.os.UserManager;
import android.provider.Settings;
import android.service.dreams.IDreamManager;
import android.util.Log;
import android.view.IWindowManager;
import android.view.View;
import android.view.Window;
import com.android.internal.widget.LockPatternUtils;
import java.util.Set;
import android.app.ActivityManager;  
import android.app.ActivityManager.MemoryInfo;
import java.util.Date;
import java.text.SimpleDateFormat;
import android.text.format.Time;
import android.content.BroadcastReceiver;
import android.content.IntentFilter; 
import java.text.ParseException;

public class StNvaCtllib {
    private static final String TAG = "android.stnvactllib.StNvaCtllib";
    private Context mContext;

    //StNvaCtllib init    
    public StNvaCtllib(Context context) {
	this.mContext = context;
    }

    //AdvSdklib api implement
 /********************************************** UI ************************************************************/

/********************************** UI ---- Navigation Bar ********************************************/    
	/**
     * Show navigation bar.
     */
    public boolean showNavigationBar() {
        SystemProperties.set("persist.navbar", "true");
        decorView.setSystemUiVisibility(
                 View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        return true;
    }
    
    public boolean hideNavigationBar() {
        SystemProperties.set("persist.navbar", "false");
        decorView.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION // hide nav bar
                    | View.SYSTEM_UI_FLAG_IMMERSIVE);
        return true;
    }
   
    public boolean isNavigationBarVisible() {
	return SystemProperties.getBoolean("persist.navbar", true);
    }
    
/******************************************************************************************************/

/************************************** UI ---- Status Bar ********************************************/

    /**
     * Show status bar.
     */
    public boolean showStatusBar() {
        SystemProperties.set("persist.statusbar", "true");
        decorView.setSystemUiVisibility(
                 View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        return true;
    }
    
    public boolean hideStatusBar() {
        SystemProperties.set("persist.statusbar", "false");
        decorView.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN // hide status bar
                    | View.SYSTEM_UI_FLAG_IMMERSIVE);
        return true;
    }

    public boolean isStatusBarVisible() {
        return SystemProperties.getBoolean("persist.statusbar", true);
    }
}

