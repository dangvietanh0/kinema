package studio.kinema.media;

import android.graphics.Bitmap;
import android.media.MediaMetadataRetriever;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Android frame-proxy extractor for video references.
 *
 * <p>{@link #extract(String, String, int, int)} starts a worker thread and
 * returns immediately. GDScript polls {@link #progress()}, {@link #done()},
 * {@link #error()}, {@link #cancel()} and {@link #result()}. Frames are JPEGs
 * in {@code <outDir>/frames/} plus a {@code reference.json} manifest that
 * matches the schema read by {@code video_reference.gd}.</p>
 */
public final class KinemaVideoFrames {
    private static final AtomicBoolean RUNNING = new AtomicBoolean(false);
    private static volatile int sProgress = 0;
    private static volatile boolean sDone = false;
    private static volatile String sError = "";
    private static volatile boolean sCancelled = false;
    private static volatile String sResult = "{}";

    private KinemaVideoFrames() {
    }

    public static String extract(String videoPath, String outDir, int fps, int maxWidth) {
        if (!RUNNING.compareAndSet(false, true)) {
            return errorJson("A frame extraction is already running.");
        }
        sProgress = 0;
        sDone = false;
        sError = "";
        sCancelled = false;
        sResult = "{}";
        final int rate = Math.max(1, fps);
        final int widthLimit = Math.max(1, maxWidth);
        Thread thread = new Thread(() -> {
            try {
                runExtract(videoPath, outDir, rate, widthLimit);
            } catch (Throwable error) {
                sError = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
                deleteTree(new File(outDir));
                sResult = errorJson(sError);
            } finally {
                RUNNING.set(false);
                sDone = true;
            }
        }, "KinemaVideoFrames");
        thread.start();
        JSONObject started = new JSONObject();
        try {
            started.put("ok", true);
            started.put("started", true);
            started.put("fps", rate);
            started.put("maxWidth", widthLimit);
        } catch (Exception ignored) {
        }
        return started.toString();
    }

    public static int progress() {
        return sProgress;
    }

    public static boolean done() {
        return sDone;
    }

    public static String error() {
        return sError == null ? "" : sError;
    }

    public static void cancel() {
        sCancelled = true;
    }

    public static String result() {
        return sResult;
    }

    private static void runExtract(String videoPath, String outDir, int fps, int maxWidth) throws Exception {
        File root = new File(outDir);
        File framesDir = new File(root, "frames");
        if (!framesDir.exists() && !framesDir.mkdirs()) {
            throw new IllegalStateException("Could not create the proxy folder: " + framesDir);
        }
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        JSONArray frames = new JSONArray();
        int width = 0;
        int height = 0;
        double duration = 0.0;
        try {
            retriever.setDataSource(videoPath);
            String durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            if (durationMs != null) {
                duration = Long.parseLong(durationMs) / 1000.0;
            }
            int count = Math.max(1, (int) Math.round(duration * fps));
            for (int index = 0; index < count; index++) {
                if (sCancelled) {
                    throw new IllegalStateException("Frame extraction cancelled.");
                }
                long timeUs = (long) index * 1000000L / fps;
                Bitmap frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST);
                if (frame == null) {
                    throw new IllegalStateException("Could not extract frame " + (index + 1) + ".");
                }
                if (width == 0) {
                    width = frame.getWidth();
                    height = frame.getHeight();
                    if (width > maxWidth) {
                        double scale = (double) maxWidth / (double) width;
                        width = maxWidth;
                        height = Math.max(2, (int) Math.round(height * scale));
                        if (height % 2 != 0) {
                            height += 1;
                        }
                    }
                }
                Bitmap output = frame;
                if (frame.getWidth() != width || frame.getHeight() != height) {
                    output = Bitmap.createScaledBitmap(frame, width, height, true);
                }
                String name = String.format("frame_%06d.jpg", index + 1);
                File file = new File(framesDir, name);
                FileOutputStream stream = new FileOutputStream(file);
                try {
                    output.compress(Bitmap.CompressFormat.JPEG, 90, stream);
                } finally {
                    stream.close();
                }
                if (output != frame) {
                    output.recycle();
                }
                frame.recycle();
                frames.put(name);
                sProgress = Math.min(99, (int) (100.0 * (index + 1) / count));
            }
        } finally {
            try {
                retriever.release();
            } catch (Exception ignored) {
            }
        }
        JSONObject manifest = new JSONObject();
        manifest.put("version", 1);
        manifest.put("fps", fps);
        manifest.put("duration", duration);
        manifest.put("width", width);
        manifest.put("height", height);
        manifest.put("frames", frames);
        FileOutputStream stream = new FileOutputStream(new File(root, "reference.json"));
        try {
            stream.write(manifest.toString().getBytes("UTF-8"));
        } finally {
            stream.close();
        }
        JSONObject result = new JSONObject();
        result.put("ok", true);
        result.put("fps", fps);
        result.put("duration", duration);
        result.put("width", width);
        result.put("height", height);
        result.put("frames", frames);
        sResult = result.toString();
        sProgress = 100;
    }

    private static String errorJson(String message) {
        JSONObject out = new JSONObject();
        try {
            out.put("ok", false);
            out.put("error", message);
        } catch (Exception ignored) {
        }
        return out.toString();
    }

    private static void deleteTree(File file) {
        if (file == null || !file.exists()) {
            return;
        }
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteTree(child);
            }
        }
        file.delete();
    }
}
