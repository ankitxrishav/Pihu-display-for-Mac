package com.pihu.display

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.net.InetSocketAddress
import kotlin.concurrent.thread

class MainActivity : Activity(), SurfaceHolder.Callback {

    private val TAG = "PihuDisplay"
    private val PORT = 27183

    private var surfaceView: SurfaceView? = null
    private var decoder: MediaCodec? = null
    private var isDecoderConfigured = false
    private var surface: Surface? = null

    @Volatile
    private var isRunning = false
    private var rxThread: Thread? = null
    private var decoderThread: Thread? = null

    private var overlayView: LinearLayout? = null
    private var statusText: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        val container = FrameLayout(this)
        container.setBackgroundColor(Color.parseColor("#121214"))

        surfaceView = SurfaceView(this)
        surfaceView?.holder?.addCallback(this)
        container.addView(surfaceView)

        val welcomeLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E0121214"))
            val paddingPx = (40 * resources.displayMetrics.density).toInt()
            setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
        }

        val catIcon = ImageView(this).apply {
            val drawableId = resources.getIdentifier("ic_cat_launcher", "mipmap", packageName)
            if (drawableId != 0) {
                setImageResource(drawableId)
            }
            val size = (128 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                bottomMargin = (24 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(catIcon)

        val titleText = TextView(this).apply {
            text = "Pihu Display"
            textSize = 28f
            setTextColor(Color.parseColor("#FFFFFF"))
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (8 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(titleText)

        statusText = TextView(this).apply {
            text = "Waiting for host connection..."
            textSize = 16f
            setTextColor(Color.parseColor("#A0A0A2"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (32 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(statusText)

        val guideBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1E1E22"))
            val pX = (24 * resources.displayMetrics.density).toInt()
            val pY = (16 * resources.displayMetrics.density).toInt()
            setPadding(pX, pY, pX, pY)
            layoutParams = LinearLayout.LayoutParams(
                (360 * resources.displayMetrics.density).toInt(),
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val guideTitle = TextView(this).apply {
            text = "Connection Guide"
            textSize = 14f
            setTextColor(Color.parseColor("#808082"))
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (12 * resources.displayMetrics.density).toInt()
            }
        }
        guideBox.addView(guideTitle)

        val guideSteps = TextView(this).apply {
            text = "1. Connect device to Mac via USB\n" +
                   "2. Enable USB Debugging in Developer Options\n" +
                   "3. Run ./run.sh on your Mac"
            textSize = 14f
            setTextColor(Color.parseColor("#D0D0D2"))
            setLineSpacing(8f, 1.1f)
        }
        guideBox.addView(guideSteps)
        welcomeLayout.addView(guideBox)

        container.addView(welcomeLayout)
        setContentView(container)

        overlayView = welcomeLayout
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d(TAG, "Surface created")
        surface = holder.surface
        startStreaming()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.d(TAG, "Surface changed: ${width}x${height}")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.d(TAG, "Surface destroyed")
        stopStreaming()
        surface = null
    }

    private fun startStreaming() {
        if (isRunning) return
        isRunning = true

        rxThread = thread(name = "PihuRxThread", priority = Thread.MAX_PRIORITY) {
            runRxLoop()
        }
    }

    private fun stopStreaming() {
        isRunning = false
        rxThread?.interrupt()
        rxThread = null
        
        decoderThread?.interrupt()
        decoderThread = null

        releaseDecoder()
    }

    private fun initDecoder(surface: Surface) {
        try {
            Log.d(TAG, "Initializing MediaCodec decoder")
            val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            
            // We configure with 1920x1080 default, but the decoder will adapt
            // when it receives the SPS/PPS NAL units.
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080)
            
            // Set low-latency properties if supported by the hardware
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            
            codec.configure(format, surface, null, 0)
            codec.start()
            
            decoder = codec
            isDecoderConfigured = true
            Log.d(TAG, "MediaCodec decoder started successfully")

            // Start decoder output pulling thread
            val myCodec = codec
            decoderThread = thread(name = "PihuDecoderThread", priority = Thread.MAX_PRIORITY) {
                val bufferInfo = MediaCodec.BufferInfo()
                while (isRunning && decoder == myCodec) {
                    try {
                        val outputBufferIndex = myCodec.dequeueOutputBuffer(bufferInfo, 10000) // 10ms timeout
                        if (outputBufferIndex >= 0) {
                            myCodec.releaseOutputBuffer(outputBufferIndex, true)
                        }
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        if (decoder != myCodec) {
                            break
                        }
                        Log.e(TAG, "Error in decoder output thread", e)
                        try { Thread.sleep(50) } catch (ex: InterruptedException) { break }
                    }
                }
                Log.d(TAG, "Decoder thread exiting for codec $myCodec")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize decoder", e)
            runOnUiThread {
                Toast.makeText(this, "Failed to init hardware decoder: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun releaseDecoder() {
        Log.d(TAG, "Releasing MediaCodec decoder")
        isDecoderConfigured = false
        val codec = decoder
        decoder = null
        codec?.let {
            try {
                it.stop()
                it.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing decoder", e)
            }
        }
    }

    private fun readExactly(inputStream: InputStream, buffer: ByteArray, length: Int): Boolean {
        var totalRead = 0
        while (totalRead < length) {
            val read = inputStream.read(buffer, totalRead, length - totalRead)
            if (read == -1) return false
            totalRead += read
        }
        return true
    }

    private fun runRxLoop() {
        val lengthBuffer = ByteArray(4)
        var payloadBuffer = ByteArray(1024 * 1024) // 1MB reusable buffer
        var serverSocket: ServerSocket? = null
        var socket: Socket? = null
        var inputStream: InputStream? = null

        while (isRunning) {
            val s = surface
            if (s == null) {
                try { Thread.sleep(100) } catch (e: InterruptedException) {}
                continue
            }

            // Ensure decoder is initialized
            if (decoder == null) {
                initDecoder(s)
            }

            try {
                runOnUiThread {
                    statusText?.text = "Waiting for host connection..."
                    overlayView?.visibility = View.VISIBLE
                }
                Log.d(TAG, "Starting ServerSocket on port $PORT...")
                val sSock = ServerSocket()
                sSock.reuseAddress = true
                sSock.bind(InetSocketAddress("127.0.0.1", PORT))
                serverSocket = sSock

                Log.d(TAG, "Waiting for host connection (adb forward)...")
                runOnUiThread {
                    Toast.makeText(this@MainActivity, "Waiting for host connection...", Toast.LENGTH_SHORT).show()
                }

                val sock = serverSocket.accept()
                socket = sock
                socket.tcpNoDelay = true
                socket.receiveBufferSize = 1024 * 1024
                inputStream = socket.getInputStream()
                Log.d(TAG, "Host connected successfully!")

                runOnUiThread {
                    Toast.makeText(this@MainActivity, "Connected to host display!", Toast.LENGTH_SHORT).show()
                    overlayView?.visibility = View.GONE
                }

                var frameCount = 0
                while (isRunning) {
                    val stream = inputStream ?: break
                    // 1. Read 4-byte length prefix
                    if (!readExactly(stream, lengthBuffer, 4)) {
                        Log.d(TAG, "Socket stream reached EOF while reading length")
                        break
                    }

                    val length = ((lengthBuffer[0].toInt() and 0xFF) shl 24) or
                                 ((lengthBuffer[1].toInt() and 0xFF) shl 16) or
                                 ((lengthBuffer[2].toInt() and 0xFF) shl 8) or
                                 (lengthBuffer[3].toInt() and 0xFF)

                    if (length <= 0 || length > 10 * 1024 * 1024) {
                        Log.e(TAG, "Invalid packet length: $length")
                        break
                    }

                    // Resize payload buffer if necessary
                    if (length > payloadBuffer.size) {
                        payloadBuffer = ByteArray(length)
                    }

                    // 2. Read exactly `length` bytes of payload
                    if (!readExactly(stream, payloadBuffer, length)) {
                        Log.d(TAG, "Socket stream reached EOF while reading payload of size $length")
                        break
                    }

                    // 3. Feed directly to decoder
                    val currentDecoder = decoder
                    if (currentDecoder != null && isDecoderConfigured) {
                        try {
                            var inputBufferIndex = -1
                            val startTime = System.currentTimeMillis()
                            while (isRunning && isDecoderConfigured && System.currentTimeMillis() - startTime < 500) {
                                inputBufferIndex = currentDecoder.dequeueInputBuffer(10000) // 10ms timeout
                                if (inputBufferIndex >= 0) {
                                    break
                                }
                            }

                            if (inputBufferIndex >= 0) {
                                val inputBuffer = currentDecoder.getInputBuffer(inputBufferIndex)
                                if (inputBuffer != null) {
                                    inputBuffer.clear()
                                    inputBuffer.put(payloadBuffer, 0, length)
                                    val pts = System.nanoTime() / 1000
                                    currentDecoder.queueInputBuffer(inputBufferIndex, 0, length, pts, 0)
                                    
                                    frameCount++
                                    if (frameCount % 60 == 0) {
                                        Log.d(TAG, "Decoded 60 frames (total: $frameCount)")
                                    }
                                }
                            } else {
                                Log.w(TAG, "Dropped packet of size $length due to decoder busy")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error feeding packet to decoder", e)
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Socket or ServerSocket error: ${e.message}")
                }
            } finally {
                try { inputStream?.close() } catch (e: Exception) {}
                try { socket?.close() } catch (e: Exception) {}
                try { serverSocket?.close() } catch (e: Exception) {}
                serverSocket = null
                socket = null
                inputStream = null
                
                releaseDecoder()
                
                runOnUiThread {
                    if (isRunning) {
                        statusText?.text = "Disconnected. Waiting for reconnection..."
                        overlayView?.visibility = View.VISIBLE
                        Toast.makeText(this@MainActivity, "Disconnected. Retrying...", Toast.LENGTH_SHORT).show()
                    }
                }
                try { Thread.sleep(1000) } catch (e: InterruptedException) { break }
            }
        }
    }
}
