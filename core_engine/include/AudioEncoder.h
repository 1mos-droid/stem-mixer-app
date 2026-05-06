#ifndef AUDIO_ENCODER_H
#define AUDIO_ENCODER_H

#include <string>
#include <vector>
#include <stdexcept>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
}

class AudioEncoder {
public:
    void encode(const std::vector<float>& planarAudio, const std::string& outputPath);
};

#endif // AUDIO_ENCODER_H
