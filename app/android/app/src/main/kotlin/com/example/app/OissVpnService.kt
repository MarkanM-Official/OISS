package com.example.app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import kotlin.concurrent.thread

class OissVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var tun2socksProcess: Process? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }
        
        if (vpnInterface == null) {
            setupVpn()
        }
        return START_STICKY
    }

    private fun setupVpn() {
        try {
            val builder = Builder()
            builder.addAddress("10.0.0.2", 24)
            builder.addRoute("0.0.0.0", 0) // Route all traffic
            builder.addDnsServer("8.8.8.8")
            builder.setSession("OISS Tunnel")
            
            vpnInterface = builder.establish()
            
            val pfd = vpnInterface
            if (pfd != null) {
                // Clear O_CLOEXEC flag so the child process can inherit this FileDescriptor
                Os.fcntlInt(pfd.fileDescriptor, OsConstants.F_SETFD, 0)
                startTun2Socks(pfd.fd)
            }
        } catch (e: Exception) {
            Log.e("OissVpn", "Failed to setup VPN", e)
            stopVpn()
        }
    }

    private fun startTun2Socks(fd: Int) {
        thread {
            try {
                // Extract binary based on architecture
                val arch = System.getProperty("os.arch")
                val assetDir = if (arch?.contains("aarch64") == true || arch?.contains("arm64") == true) {
                    "tun2socks/arm64-v8a"
                } else {
                    "tun2socks/armeabi-v7a"
                }
                
                val exeFile = File(filesDir, "tun2socks")
                // Always overwrite for safety in development, or check length
                val assetManager = assets
                val inputStream: InputStream = assetManager.open("$assetDir/tun2socks")
                val outputStream = FileOutputStream(exeFile)
                inputStream.copyTo(outputStream)
                inputStream.close()
                outputStream.close()
                exeFile.setExecutable(true)

                Log.d("OissVpn", "Starting tun2socks with fd: $fd")
                
                val pb = ProcessBuilder(
                    exeFile.absolutePath,
                    "-device", "fd://$fd",
                    "-proxy", "socks5://127.0.0.1:1080",
                    "-loglevel", "debug"
                )
                pb.redirectErrorStream(true)
                tun2socksProcess = pb.start()
                
                val reader = tun2socksProcess?.inputStream?.bufferedReader()
                while (true) {
                    val line = reader?.readLine() ?: break
                    Log.d("tun2socks", line)
                }
            } catch (e: Exception) {
                Log.e("OissVpn", "tun2socks failed", e)
            }
        }
    }

    private fun stopVpn() {
        try {
            tun2socksProcess?.destroy()
            tun2socksProcess = null
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.e("OissVpn", "Error stopping VPN", e)
        }
        stopSelf()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
