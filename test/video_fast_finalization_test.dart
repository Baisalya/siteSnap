import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

const _baseSignature = VideoStreamSignature(
  videoCodec: 'h264',
  profile: 'High',
  pixelFormat: 'yuv420p',
  codecTag: 'avc1',
  videoTimeBase: '1/90000',
  width: 1920,
  height: 1080,
  level: 40,
  frameRate: 30,
  rotationDegrees: 0,
  hasAudio: true,
  audioCodec: 'aac',
  audioProfile: 'LC',
  audioTimeBase: '1/48000',
  sampleRate: 48000,
  channels: 2,
  channelLayout: 'stereo',
);

VideoStreamSignature _signature({
  String videoCodec = 'h264',
  String profile = 'High',
  String pixelFormat = 'yuv420p',
  String codecTag = 'avc1',
  String videoTimeBase = '1/90000',
  int width = 1920,
  int height = 1080,
  int level = 40,
  double frameRate = 30,
  int rotationDegrees = 0,
  bool hasAudio = true,
  String audioCodec = 'aac',
  String audioProfile = 'LC',
  String audioTimeBase = '1/48000',
  int sampleRate = 48000,
  int channels = 2,
  String channelLayout = 'stereo',
}) {
  return VideoStreamSignature(
    videoCodec: videoCodec,
    profile: profile,
    pixelFormat: pixelFormat,
    codecTag: codecTag,
    videoTimeBase: videoTimeBase,
    width: width,
    height: height,
    level: level,
    frameRate: frameRate,
    rotationDegrees: rotationDegrees,
    hasAudio: hasAudio,
    audioCodec: audioCodec,
    audioProfile: audioProfile,
    audioTimeBase: audioTimeBase,
    sampleRate: sampleRate,
    channels: channels,
    channelLayout: channelLayout,
  );
}

void main() {
  test('identical definitive streams are eligible for stream-copy concat', () {
    expect(_baseSignature.isDefinitiveForStreamCopy, isTrue);
    expect(
      _baseSignature.isStreamCopyCompatibleWith(_signature()),
      isTrue,
    );
  });

  test('rotation or encoded geometry mismatch blocks fast concat', () {
    expect(
      _baseSignature.isStreamCopyCompatibleWith(
        _signature(rotationDegrees: 90),
      ),
      isFalse,
    );
    expect(
      _baseSignature.isStreamCopyCompatibleWith(_signature(width: 1280)),
      isFalse,
    );
  });

  test('codec and audio layout mismatch block fast concat', () {
    expect(
      _baseSignature.isStreamCopyCompatibleWith(
        _signature(videoCodec: 'hevc'),
      ),
      isFalse,
    );
    expect(
      _baseSignature.isStreamCopyCompatibleWith(
        _signature(channelLayout: 'mono', channels: 1),
      ),
      isFalse,
    );
  });

  test('small reported frame-rate rounding difference is tolerated', () {
    expect(
      _baseSignature.isStreamCopyCompatibleWith(
        _signature(frameRate: 29.995),
      ),
      isTrue,
    );
  });

  test('unknown stream metadata fails closed', () {
    final unknown = _signature(videoTimeBase: '', frameRate: 0);
    expect(unknown.isDefinitiveForStreamCopy, isFalse);
    expect(_baseSignature.isStreamCopyCompatibleWith(unknown), isFalse);
  });
}
