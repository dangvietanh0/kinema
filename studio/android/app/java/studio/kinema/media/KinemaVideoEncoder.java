package studio.kinema.media;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.media.MediaMetadataRetriever;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Real H.264 + AAC MP4 encoder for Kinema Studio.
 *
 * <p>One encode runs at a time. GDScript calls {@link #encode(String, String)}
 * and polls {@link #progress()}, {@link #done()}, {@link #error()} and
 * {@link #cancel()}. The encoder decodes numbered PNG frames, converts them to
 * I420, encodes with MediaCodec, decodes and mixes the manifest audio to
 * 44.1 kHz stereo, encodes AAC and muxes both tracks with MediaMuxer.</p>
 *
 * <p>This class is compiled into the Android app module by
 * scripts/stage-android.sh. It is never loaded on desktop.</p>
 */
public final class KinemaVideoEncoder {
    private static final String TAG = "KinemaVideoEncoder";
    private static final int AUDIO_SAMPLE_RATE = 44100;
    private static final int AUDIO_CHANNELS = 2;
    private static final long DEQUEUE_TIMEOUT_US = 10000L;
    private static final AtomicBoolean RUNNING = new AtomicBoolean(false);

    private static volatile int sProgress = 0;
    private static volatile boolean sDone = false;
    private static volatile String sError = "";
    private static volatile boolean sCancelled = false;

    private KinemaVideoEncoder() {
    }

    public static void encode(String manifestJson, String outputPath) {
        if (!RUNNING.compareAndSet(false, true)) {
            return;
        }
        sProgress = 0;
        sDone = false;
        sError = "";
        sCancelled = false;
        Thread thread = new Thread(() -> {
            try {
                runEncode(manifestJson, outputPath);
                if (sCancelled) {
                    sError = "Encode cancelled.";
                } else {
                    sProgress = 100;
                }
            } catch (CancelledException cancelled) {
                sCancelled = true;
                sError = "Encode cancelled.";
                deleteQuietly(outputPath);
            } catch (Throwable error) {
                sError = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
                deleteQuietly(outputPath);
            } finally {
                RUNNING.set(false);
                sDone = true;
            }
        }, "KinemaVideoEncoder");
        thread.start();
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

    public static String capabilities() {
        JSONObject out = new JSONObject();
        try {
            JSONArray profiles = new JSONArray();
            JSONArray levels = new JSONArray();
            int maxWidth = 0;
            int maxHeight = 0;
            boolean highProfile = false;
            boolean vbr = false;
            MediaCodecList list = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
            for (MediaCodecInfo info : list.getCodecInfos()) {
                if (info.isEncoder()) {
                    for (String type : info.getSupportedTypes()) {
                        if (!type.equalsIgnoreCase(MediaFormat.MIMETYPE_VIDEO_AVC)) {
                            continue;
                        }
                        MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
                        MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
                        if (video != null) {
                            maxWidth = Math.max(maxWidth, video.getSupportedWidths().getUpper());
                            maxHeight = Math.max(maxHeight, video.getSupportedHeights().getUpper());
                        }
                        if (supportsVbr(caps)) {
                            vbr = true;
                        }
                        for (MediaCodecInfo.CodecProfileLevel level : caps.profileLevels) {
                            profiles.put(level.profile);
                            levels.put(level.level);
                            if (level.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh) {
                                highProfile = true;
                            }
                        }
                    }
                }
            }
            JSONArray aac = new JSONArray();
            java.util.LinkedHashSet<Integer> aacRates = new java.util.LinkedHashSet<>();
            for (MediaCodecInfo info : list.getCodecInfos()) {
                if (!info.isEncoder()) {
                    continue;
                }
                for (String type : info.getSupportedTypes()) {
                    if (!type.equalsIgnoreCase(MediaFormat.MIMETYPE_AUDIO_AAC)) {
                        continue;
                    }
                    MediaCodecInfo.CodecCapabilities audioCaps = info.getCapabilitiesForType(type);
                    MediaCodecInfo.AudioCapabilities audio = audioCaps.getAudioCapabilities();
                    if (audio != null) {
                        for (int rate : audio.getSupportedSampleRates()) {
                            aacRates.add(rate);
                        }
                    }
                }
            }
            for (int rate : aacRates) {
                aac.put(rate);
            }
            out.put("supported", true);
            out.put("avc", "video/avc");
            out.put("profiles", profiles);
            out.put("levels", levels);
            out.put("max_width", maxWidth);
            out.put("max_height", maxHeight);
            out.put("aac", aac);
            out.put("supports_4k", maxWidth >= 3840 && maxHeight >= 2160);
            out.put("supports_1440p", maxWidth >= 2560 && maxHeight >= 1440);
            out.put("supports_high_profile", highProfile);
            out.put("supports_vbr", vbr);
        } catch (Throwable error) {
            out = new JSONObject();
            try {
                out.put("supported", false);
                out.put("error", error.getMessage());
                out.put("supports_4k", false);
                out.put("supports_1440p", false);
                out.put("supports_high_profile", false);
                out.put("supports_vbr", false);
            } catch (Exception ignored) {
            }
        }
        return out.toString();
    }

    public static String probe(String path) {
        JSONObject out = new JSONObject();
        MediaExtractor extractor = new MediaExtractor();
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        try {
            extractor.setDataSource(path);
            boolean video = false;
            boolean audio = false;
            int width = 0;
            int height = 0;
            String videoMime = "";
            String audioMime = "";
            long durationUs = 0L;
            for (int index = 0; index < extractor.getTrackCount(); index++) {
                MediaFormat format = extractor.getTrackFormat(index);
                String mime = format.getString(MediaFormat.KEY_MIME);
                if (mime == null) {
                    continue;
                }
                if (mime.startsWith("video/")) {
                    video = true;
                    videoMime = mime;
                    width = format.containsKey(MediaFormat.KEY_WIDTH) ? format.getInteger(MediaFormat.KEY_WIDTH) : width;
                    height = format.containsKey(MediaFormat.KEY_HEIGHT) ? format.getInteger(MediaFormat.KEY_HEIGHT) : height;
                } else if (mime.startsWith("audio/")) {
                    audio = true;
                    audioMime = mime;
                }
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = Math.max(durationUs, format.getLong(MediaFormat.KEY_DURATION));
                }
            }
            retriever.setDataSource(path);
            String durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            if (durationMs != null) {
                durationUs = Math.max(durationUs, Long.parseLong(durationMs) * 1000L);
            }
            out.put("duration", durationUs / 1000000.0);
            out.put("width", width);
            out.put("height", height);
            out.put("video", video);
            out.put("audio", audio);
            out.put("videoMime", videoMime);
            out.put("audioMime", audioMime);
            out.put("size", new File(path).length());
        } catch (Throwable error) {
            try {
                out.put("error", error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage());
            } catch (Exception ignored) {
            }
        } finally {
            try {
                extractor.release();
            } catch (Exception ignored) {
            }
            try {
                retriever.release();
            } catch (Exception ignored) {
            }
        }
        return out.toString();
    }

    // ---------------------------------------------------------------------
    // Encode pipeline
    // ---------------------------------------------------------------------

    private static void runEncode(String manifestJson, String outputPath) throws Exception {
        JSONObject manifest = new JSONObject(manifestJson);
        int width = manifest.getInt("width");
        int height = manifest.getInt("height");
        int fps = Math.max(1, manifest.getInt("fps"));
        int bitrate = manifest.getInt("bitrate");
        int audioBitrate = Math.max(8000, manifest.optInt("audioBitrate", 192000));
        String frameDir = manifest.getString("frameDir");
        String pattern = manifest.getString("framePattern");
        int frameCount = manifest.getInt("frameCount");
        JSONArray audioEntries = manifest.optJSONArray("audio");
        File directory = new File(frameDir);
        if (!directory.isDirectory()) {
            throw new IllegalStateException("Frame directory does not exist: " + frameDir);
        }
        File output = new File(outputPath);
        File parent = output.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IllegalStateException("Could not create the output folder.");
        }

        List<Sample> videoSamples = encodeVideo(directory, pattern, frameCount, width, height, fps, bitrate);
        sProgress = 85;
        List<Sample> audioSamples = new ArrayList<>();
        MediaFormat audioFormat = null;
        if (audioEntries != null && audioEntries.length() > 0) {
            short[] mixed = mixAudio(audioEntries, frameCount, fps);
            if (mixed.length > 0) {
                EncodedAudio encoded = encodeAudio(mixed, audioBitrate);
                audioFormat = encoded.format;
                audioSamples = encoded.samples;
            }
        }
        sProgress = 95;

        MediaMuxer muxer = new MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        int videoTrack = -1;
        int audioTrack = -1;
        try {
            if (videoSamples.isEmpty()) {
                throw new IllegalStateException("The video encoder produced no frames.");
            }
            videoTrack = muxer.addTrack(videoSamples.get(0).format);
            if (audioFormat != null) {
                audioTrack = muxer.addTrack(audioFormat);
            }
            muxer.start();
            List<Sample> all = new ArrayList<>();
            for (Sample sample : videoSamples) {
                sample.track = videoTrack;
                all.add(sample);
            }
            for (Sample sample : audioSamples) {
                sample.track = audioTrack;
                all.add(sample);
            }
            Collections.sort(all, new Comparator<Sample>() {
                @Override
                public int compare(Sample left, Sample right) {
                    return Long.compare(left.info.presentationTimeUs, right.info.presentationTimeUs);
                }
            });
            for (Sample sample : all) {
                if (sCancelled) {
                    throw new CancelledException();
                }
                ByteBuffer buffer = ByteBuffer.wrap(sample.data);
                muxer.writeSampleData(sample.track, buffer, sample.info);
            }
        } finally {
            try {
                muxer.stop();
            } catch (Exception ignored) {
            }
            try {
                muxer.release();
            } catch (Exception ignored) {
            }
        }
        if (!output.exists() || output.length() <= 0) {
            throw new IllegalStateException("The MP4 file is empty.");
        }
    }

    private static List<Sample> encodeVideo(File directory, String pattern, int frameCount,
                                            int width, int height, int fps, int bitrate) throws Exception {
        MediaCodecInfo codecInfo = findVideoEncoder(width, height);
        MediaCodecInfo.CodecCapabilities caps = codecInfo == null
                ? null
                : codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC);
        int colorFormat = caps == null
                ? MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
                : selectColorFormat(caps);
        boolean vbr = caps != null && supportsVbr(caps);
        MediaFormat format = buildVideoFormat(width, height, fps, bitrate, colorFormat, vbr);
        int[] profileLevel = caps == null ? null : selectProfileLevel(caps, width, height, fps);
        boolean profileKeysSet = profileLevel != null;
        if (profileKeysSet) {
            format.setInteger(MediaFormat.KEY_PROFILE, profileLevel[0]);
            format.setInteger(MediaFormat.KEY_LEVEL, profileLevel[1]);
        }
        MediaCodec encoder = codecInfo == null
                ? MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                : MediaCodec.createByCodecName(codecInfo.getName());
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        } catch (Exception rejected) {
            if (!profileKeysSet) {
                throw rejected;
            }
            // Some encoders advertise a profile/level they then reject at
            // configure time. Do the retry once, and only once, without those
            // two keys; every other format key stays exactly as requested.
            MediaFormat fallback = buildVideoFormat(width, height, fps, bitrate, colorFormat, vbr);
            encoder.configure(fallback, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        }
        encoder.start();
        List<Sample> samples = new ArrayList<>();
        MediaFormat outputFormat = null;
        byte[] yuv = new byte[width * height * 3 / 2];
        try {
            for (int index = 0; index < frameCount; index++) {
                if (sCancelled) {
                    throw new CancelledException();
                }
                String name = String.format(pattern, index + 1);
                File frameFile = new File(directory, name);
                Bitmap bitmap = BitmapFactory.decodeFile(frameFile.getAbsolutePath());
                if (bitmap == null) {
                    throw new IllegalStateException("Could not decode frame: " + frameFile.getName());
                }
                if (bitmap.getWidth() != width || bitmap.getHeight() != height) {
                    Bitmap scaled = Bitmap.createScaledBitmap(bitmap, width, height, true);
                    if (scaled != bitmap) {
                        bitmap.recycle();
                        bitmap = scaled;
                    }
                }
                if (colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar) {
                    fillNV12(bitmap, yuv, width, height);
                } else {
                    fillI420(bitmap, yuv, width, height);
                }
                bitmap.recycle();
                int inputIndex = encoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US * 10L);
                if (inputIndex >= 0) {
                    ByteBuffer input = encoder.getInputBuffer(inputIndex);
                    input.clear();
                    input.put(yuv);
                    long ptsUs = (long) index * 1000000L / fps;
                    encoder.queueInputBuffer(inputIndex, 0, yuv.length, ptsUs, 0);
                }
                MediaFormat changed = drainEncoder(encoder, samples, false);
                if (changed != null) {
                    outputFormat = changed;
                }
                sProgress = Math.min(84, 5 + (int) (80.0 * (index + 1) / Math.max(1, frameCount)));
            }
            int inputIndex = encoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US * 10L);
            if (inputIndex >= 0) {
                encoder.queueInputBuffer(inputIndex, 0, 0, (long) frameCount * 1000000L / fps,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            }
            MediaFormat changed = drainEncoder(encoder, samples, true);
            if (changed != null) {
                outputFormat = changed;
            }
        } finally {
            try {
                encoder.stop();
            } catch (Exception ignored) {
            }
            encoder.release();
        }
        if (outputFormat == null) {
            throw new IllegalStateException("The video encoder never reported an output format.");
        }
        for (Sample sample : samples) {
            sample.format = outputFormat;
        }
        return samples;
    }

    private static MediaFormat drainEncoder(MediaCodec encoder, List<Sample> samples, boolean endOfStream) {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        MediaFormat changed = null;
        int idle = 0;
        while (true) {
            int index = encoder.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US);
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!endOfStream) {
                    break;
                }
                if (++idle > 100) {
                    break;
                }
                continue;
            }
            idle = 0;
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                changed = encoder.getOutputFormat();
                continue;
            }
            if (index < 0) {
                continue;
            }
            ByteBuffer buffer = encoder.getOutputBuffer(index);
            if (buffer != null && info.size > 0 && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                buffer.position(info.offset);
                buffer.limit(info.offset + info.size);
                byte[] data = new byte[info.size];
                buffer.get(data);
                samples.add(new Sample(data, info));
            }
            encoder.releaseOutputBuffer(index, false);
            if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                break;
            }
        }
        return changed;
    }

    private static MediaCodecInfo findVideoEncoder(int width, int height) {
        MediaCodecList list = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
        for (MediaCodecInfo info : list.getCodecInfos()) {
            if (!info.isEncoder()) {
                continue;
            }
            for (String type : info.getSupportedTypes()) {
                if (!type.equalsIgnoreCase(MediaFormat.MIMETYPE_VIDEO_AVC)) {
                    continue;
                }
                MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
                MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
                if (video == null || video.isSizeSupported(width, height)) {
                    return info;
                }
            }
        }
        return null;
    }

    private static int selectColorFormat(MediaCodecInfo.CodecCapabilities caps) {
        for (int candidate : caps.colorFormats) {
            if (candidate == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar) {
                return candidate;
            }
        }
        return MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar;
    }

    /** The real encoder format. Profile/level are added separately so the
     *  one-retry fallback can rebuild this without them. */
    private static MediaFormat buildVideoFormat(int width, int height, int fps, int bitrate,
                                                int colorFormat, boolean vbr) {
        MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat);
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
        format.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
        if (vbr) {
            format.setInteger(MediaFormat.KEY_BITRATE_MODE,
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR);
        }
        return format;
    }

    /** VBR is only requested when this encoder advertises the mode. */
    private static boolean supportsVbr(MediaCodecInfo.CodecCapabilities caps) {
        MediaCodecInfo.EncoderCapabilities encoderCaps = caps.getEncoderCapabilities();
        return encoderCaps != null && encoderCaps.isBitrateModeSupported(
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR);
    }

    /** Prefer High, then Main, then Baseline, but only a profile the codec
     *  actually advertises. Returns {profile, level} or null. */
    private static int[] selectProfileLevel(MediaCodecInfo.CodecCapabilities caps,
                                            int width, int height, int fps) {
        int profile = 0;
        if (hasProfile(caps, MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)) {
            profile = MediaCodecInfo.CodecProfileLevel.AVCProfileHigh;
        } else if (hasProfile(caps, MediaCodecInfo.CodecProfileLevel.AVCProfileMain)) {
            profile = MediaCodecInfo.CodecProfileLevel.AVCProfileMain;
        } else if (hasProfile(caps, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)) {
            profile = MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline;
        }
        if (profile == 0) {
            return null;
        }
        int level = selectLevel(caps, profile, width, height, fps);
        if (level == 0) {
            return null;
        }
        return new int[]{profile, level};
    }

    private static boolean hasProfile(MediaCodecInfo.CodecCapabilities caps, int profile) {
        for (MediaCodecInfo.CodecProfileLevel level : caps.profileLevels) {
            if (level.profile == profile) {
                return true;
            }
        }
        return false;
    }

    /** Smallest advertised level that covers the frame size and frame rate.
     *  When none covers the target, use the highest advertised level and let
     *  the configure retry drop the keys. Never invent an unadvertised level. */
    private static int selectLevel(MediaCodecInfo.CodecCapabilities caps, int profile,
                                   int width, int height, int fps) {
        int best = 0;
        int highest = 0;
        for (MediaCodecInfo.CodecProfileLevel entry : caps.profileLevels) {
            if (entry.profile != profile) {
                continue;
            }
            if (highest == 0 || entry.level > highest) {
                highest = entry.level;
            }
            if (levelCovers(entry.level, width, height, fps)
                    && (best == 0 || entry.level < best)) {
                best = entry.level;
            }
        }
        return best != 0 ? best : highest;
    }

    /** H.264 level limits: {max frame size in macroblocks, max macroblocks/s}. */
    private static long[] levelCapacity(int level) {
        switch (level) {
            case MediaCodecInfo.CodecProfileLevel.AVCLevel1:
            case MediaCodecInfo.CodecProfileLevel.AVCLevel1b:
                return new long[]{99L, 1485L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel11:
                return new long[]{396L, 3000L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel12:
                return new long[]{396L, 6000L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel13:
            case MediaCodecInfo.CodecProfileLevel.AVCLevel2:
                return new long[]{396L, 11880L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel21:
                return new long[]{792L, 19800L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel22:
            case MediaCodecInfo.CodecProfileLevel.AVCLevel3:
                return new long[]{1620L, 40500L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel31:
                return new long[]{3600L, 108000L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel32:
                return new long[]{5120L, 216000L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel4:
            case MediaCodecInfo.CodecProfileLevel.AVCLevel41:
                return new long[]{8192L, 245760L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel42:
                return new long[]{8704L, 522240L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel5:
                return new long[]{22080L, 589824L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel51:
                return new long[]{36864L, 983040L};
            case MediaCodecInfo.CodecProfileLevel.AVCLevel52:
                return new long[]{36864L, 2073600L};
            default:
                return null;
        }
    }

    private static boolean levelCovers(int level, int width, int height, int fps) {
        long[] capacity = levelCapacity(level);
        if (capacity == null) {
            return false;
        }
        long macroblockWidth = (width + 15) / 16;
        long macroblockHeight = (height + 15) / 16;
        long frameSize = macroblockWidth * macroblockHeight;
        long frameRate = frameSize * fps;
        return frameSize <= capacity[0] && frameRate <= capacity[1];
    }

    private static void fillNV12(Bitmap bitmap, byte[] out, int width, int height) {
        int frameSize = width * height;
        int[] argb = new int[width];
        for (int y = 0; y < height; y++) {
            bitmap.getPixels(argb, 0, width, 0, y, width, 1);
            for (int x = 0; x < width; x++) {
                int color = argb[x];
                int r = (color >> 16) & 0xFF;
                int g = (color >> 8) & 0xFF;
                int b = color & 0xFF;
                int yValue = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
                out[y * width + x] = (byte) clamp(yValue);
                if ((y & 1) == 0 && (x & 1) == 0) {
                    int uValue = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                    int vValue = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                    int chromaIndex = frameSize + (y / 2) * width + (x / 2) * 2;
                    out[chromaIndex] = (byte) clamp(uValue);
                    out[chromaIndex + 1] = (byte) clamp(vValue);
                }
            }
        }
    }

    private static void fillI420(Bitmap bitmap, byte[] out, int width, int height) {
        int frameSize = width * height;
        int chromaSize = frameSize / 4;
        int uOffset = frameSize;
        int vOffset = frameSize + chromaSize;
        int[] argb = new int[width];
        for (int y = 0; y < height; y++) {
            bitmap.getPixels(argb, 0, width, 0, y, width, 1);
            for (int x = 0; x < width; x++) {
                int color = argb[x];
                int r = (color >> 16) & 0xFF;
                int g = (color >> 8) & 0xFF;
                int b = color & 0xFF;
                int yValue = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
                out[y * width + x] = (byte) clamp(yValue);
                if ((y & 1) == 0 && (x & 1) == 0) {
                    int uValue = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                    int vValue = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                    int chromaIndex = (y / 2) * (width / 2) + (x / 2);
                    out[uOffset + chromaIndex] = (byte) clamp(uValue);
                    out[vOffset + chromaIndex] = (byte) clamp(vValue);
                }
            }
        }
    }

    private static short[] mixAudio(JSONArray entries, int frameCount, int fps) throws Exception {
        double duration = (double) frameCount / (double) fps;
        int totalFrames = Math.max(1, (int) Math.ceil(duration * AUDIO_SAMPLE_RATE));
        short[] mix = new short[totalFrames * AUDIO_CHANNELS];
        for (int index = 0; index < entries.length(); index++) {
            JSONObject entry = entries.getJSONObject(index);
            String path = entry.getString("path");
            AudioPcm source = decodeAudio(path);
            if (source == null || source.samples.length == 0) {
                throw new IllegalStateException("Could not decode audio: " + path);
            }
            double start = entry.optDouble("start", 0.0);
            double trimStart = entry.optDouble("trimStart", 0.0);
            double trimEnd = entry.optDouble("trimEnd", 0.0);
            double volume = entry.optDouble("volume", 1.0);
            double fadeIn = entry.optDouble("fadeIn", 0.0);
            double fadeOut = entry.optDouble("fadeOut", 0.0);
            double trackDuration = trimEnd - trimStart;
            if (trackDuration <= 0.0) {
                continue;
            }
            int first = (int) Math.floor(start * AUDIO_SAMPLE_RATE);
            int last = Math.min(totalFrames, (int) Math.ceil((start + trackDuration) * AUDIO_SAMPLE_RATE));
            for (int outFrame = Math.max(0, first); outFrame < last; outFrame++) {
                if (sCancelled) {
                    throw new CancelledException();
                }
                double sequenceTime = (double) outFrame / AUDIO_SAMPLE_RATE;
                double envelope = fadeEnvelope(sequenceTime, start, trimStart, trimEnd, fadeIn, fadeOut);
                if (envelope <= 0.0) {
                    continue;
                }
                double sourceTime = trimStart + (sequenceTime - start);
                int sourceFrame = (int) Math.floor(sourceTime * source.sampleRate);
                if (sourceFrame < 0 || sourceFrame >= source.frameCount()) {
                    continue;
                }
                double gain = volume * envelope;
                int left = source.sample(sourceFrame, 0);
                int right = source.channels > 1 ? source.sample(sourceFrame, 1) : left;
                int base = outFrame * AUDIO_CHANNELS;
                mix[base] = (short) clamp(mix[base] + left * gain);
                mix[base + 1] = (short) clamp(mix[base + 1] + right * gain);
            }
        }
        return mix;
    }

    private static double fadeEnvelope(double time, double start, double trimStart, double trimEnd,
                                       double fadeIn, double fadeOut) {
        double duration = trimEnd - trimStart;
        if (duration <= 0.0) {
            return 0.0;
        }
        double local = time - start;
        if (local < 0.0 || local > duration) {
            return 0.0;
        }
        double envelope = 1.0;
        double in = Math.min(fadeIn, duration);
        double out = Math.min(fadeOut, duration);
        if (in + out > duration) {
            double scale = duration / (in + out);
            in *= scale;
            out *= scale;
        }
        if (in > 0.0 && local < in) {
            envelope = Math.min(envelope, smoothstep(local / in));
        }
        if (out > 0.0 && local > duration - out) {
            envelope = Math.min(envelope, smoothstep((duration - local) / out));
        }
        return Math.max(0.0, Math.min(1.0, envelope));
    }

    private static double smoothstep(double value) {
        double t = Math.max(0.0, Math.min(1.0, value));
        return t * t * (3.0 - 2.0 * t);
    }

    private static AudioPcm decodeAudio(String path) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
        extractor.setDataSource(path);
        int trackIndex = -1;
        MediaFormat format = null;
        for (int index = 0; index < extractor.getTrackCount(); index++) {
            MediaFormat candidate = extractor.getTrackFormat(index);
            String mime = candidate.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("audio/")) {
                trackIndex = index;
                format = candidate;
                break;
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release();
            throw new IllegalStateException("No audio track in " + path);
        }
        extractor.selectTrack(trackIndex);
        String mime = format.getString(MediaFormat.KEY_MIME);
        MediaCodec decoder = MediaCodec.createDecoderByType(mime);
        decoder.configure(format, null, null, 0);
        decoder.start();
        int sampleRate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                ? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : AUDIO_SAMPLE_RATE;
        int channels = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                ? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : 1;
        List<short[]> chunks = new ArrayList<>();
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        boolean inputDone = false;
        boolean outputDone = false;
        while (!outputDone) {
            if (sCancelled) {
                throw new CancelledException();
            }
            if (!inputDone) {
                int inputIndex = decoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US);
                if (inputIndex >= 0) {
                    ByteBuffer input = decoder.getInputBuffer(inputIndex);
                    int size = extractor.readSampleData(input, 0);
                    if (size < 0) {
                        decoder.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                        inputDone = true;
                    } else {
                        decoder.queueInputBuffer(inputIndex, 0, size, extractor.getSampleTime(), 0);
                        extractor.advance();
                    }
                }
            }
            int outputIndex = decoder.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US);
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat outputFormat = decoder.getOutputFormat();
                sampleRate = outputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                        ? outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) : sampleRate;
                channels = outputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                        ? outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : channels;
            } else if (outputIndex >= 0) {
                ByteBuffer output = decoder.getOutputBuffer(outputIndex);
                if (output != null && info.size > 0) {
                    output.position(info.offset);
                    output.limit(info.offset + info.size);
                    short[] chunk = new short[info.size / 2];
                    output.order(ByteOrder.nativeOrder()).asShortBuffer().get(chunk);
                    chunks.add(chunk);
                }
                decoder.releaseOutputBuffer(outputIndex, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true;
                }
            }
        }
        decoder.stop();
        decoder.release();
        extractor.release();
        int total = 0;
        for (short[] chunk : chunks) {
            total += chunk.length;
        }
        short[] samples = new short[total];
        int offset = 0;
        for (short[] chunk : chunks) {
            System.arraycopy(chunk, 0, samples, offset, chunk.length);
            offset += chunk.length;
        }
        return new AudioPcm(samples, sampleRate, channels);
    }

    private static EncodedAudio encodeAudio(short[] pcm, int bitrate) throws Exception {
        MediaFormat format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC,
                AUDIO_SAMPLE_RATE, AUDIO_CHANNELS);
        format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384);
        MediaCodec encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        encoder.start();
        List<Sample> samples = new ArrayList<>();
        MediaFormat outputFormat = null;
        try {
            int frame = 0;
            while (frame < pcm.length / AUDIO_CHANNELS) {
                if (sCancelled) {
                    throw new CancelledException();
                }
                int inputIndex = encoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US * 10L);
                if (inputIndex < 0) {
                    continue;
                }
                ByteBuffer input = encoder.getInputBuffer(inputIndex);
                input.clear();
                int frames = Math.min(1024, pcm.length / AUDIO_CHANNELS - frame);
                ShortBuffer shorts = input.order(ByteOrder.nativeOrder()).asShortBuffer();
                shorts.put(pcm, frame * AUDIO_CHANNELS, frames * AUDIO_CHANNELS);
                long ptsUs = (long) frame * 1000000L / AUDIO_SAMPLE_RATE;
                encoder.queueInputBuffer(inputIndex, 0, frames * AUDIO_CHANNELS * 2, ptsUs, 0);
                frame += frames;
                MediaFormat changed = drainEncoder(encoder, samples, false);
                if (changed != null) {
                    outputFormat = changed;
                }
            }
            int inputIndex = encoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US * 10L);
            if (inputIndex >= 0) {
                encoder.queueInputBuffer(inputIndex, 0, 0, (long) frame * 1000000L / AUDIO_SAMPLE_RATE,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            }
            MediaFormat changed = drainEncoder(encoder, samples, true);
            if (changed != null) {
                outputFormat = changed;
            }
        } finally {
            try {
                encoder.stop();
            } catch (Exception ignored) {
            }
            encoder.release();
        }
        for (Sample sample : samples) {
            sample.format = outputFormat;
        }
        return new EncodedAudio(outputFormat, samples);
    }

    private static int clamp(double value) {
        return (int) Math.max(0, Math.min(255, Math.round(value)));
    }

    private static int clamp(int value) {
        return Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, value));
    }

    private static void deleteQuietly(String path) {
        try {
            File file = new File(path);
            if (file.exists()) {
                file.delete();
            }
        } catch (Exception ignored) {
        }
    }

    private static final class Sample {
        final byte[] data;
        final MediaCodec.BufferInfo info;
        MediaFormat format;
        int track;

        Sample(byte[] data, MediaCodec.BufferInfo info) {
            this.data = data;
            this.info = new MediaCodec.BufferInfo();
            // The payload was copied out of the codec buffer into a byte[] that
            // starts at index 0, so the muxer must not re-apply the codec offset.
            this.info.set(0, info.size, info.presentationTimeUs, info.flags);
        }
    }

    private static final class EncodedAudio {
        final MediaFormat format;
        final List<Sample> samples;

        EncodedAudio(MediaFormat format, List<Sample> samples) {
            this.format = format;
            this.samples = samples;
        }
    }

    private static final class AudioPcm {
        final short[] samples;
        final int sampleRate;
        final int channels;

        AudioPcm(short[] samples, int sampleRate, int channels) {
            this.samples = samples;
            this.sampleRate = Math.max(1, sampleRate);
            this.channels = Math.max(1, channels);
        }

        int frameCount() {
            return samples.length / channels;
        }

        int sample(int frame, int channel) {
            int index = frame * channels + Math.min(channel, channels - 1);
            return index >= 0 && index < samples.length ? samples[index] : 0;
        }
    }

    private static final class CancelledException extends Exception {
        CancelledException() {
            super("Encode cancelled.");
        }
    }
}
