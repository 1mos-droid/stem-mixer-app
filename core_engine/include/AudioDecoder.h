#ifndef AUDIO_DECODER_H
#define AUDIO_DECODER_H

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

class AudioDecoder {
public:
    AudioDecoder(const std::string& path);
    std::vector<float> decode();

private:
    std::string filepath;
};

#endif // AUDIO_DECODER_H
