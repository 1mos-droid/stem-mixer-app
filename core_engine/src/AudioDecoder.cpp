#include "AudioDecoder.h"
#include <iostream>

AudioDecoder::AudioDecoder(const std::string& path) : filepath(path) {}

std::vector<float> AudioDecoder::decode() {
    AVFormatContext* formatContext = nullptr;
    AVCodecContext* codecContext = nullptr;
    SwrContext* swrContext = nullptr;
    AVPacket* packet = nullptr;
    AVFrame* frame = nullptr;
    uint8_t** out_data = nullptr;
    int max_out_samples = 4096;

    std::vector<float> leftBuffer;
    std::vector<float> rightBuffer;

    auto cleanup = [&]() {
        if (out_data) {
            av_freep(&out_data[0]);
            av_freep(&out_data);
        }
        if (frame) av_frame_free(&frame);
        if (packet) av_packet_free(&packet);
        if (swrContext) swr_free(&swrContext);
        if (codecContext) avcodec_free_context(&codecContext);
        if (formatContext) avformat_close_input(&formatContext);
    };

    try {
        // 1. Open Input
        if (avformat_open_input(&formatContext, filepath.c_str(), nullptr, nullptr) != 0) {
            throw std::runtime_error("Could not open file: " + filepath);
        }

        if (avformat_find_stream_info(formatContext, nullptr) < 0) {
            throw std::runtime_error("Could not find stream information");
        }

        // 2. Find Audio Stream
        int audioStreamIndex = -1;
        for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
            if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                audioStreamIndex = i;
                break;
            }
        }

        if (audioStreamIndex == -1) {
            throw std::runtime_error("Could not find audio stream");
        }

        // 3. Codec Setup
        const AVCodec* decoder = avcodec_find_decoder(formatContext->streams[audioStreamIndex]->codecpar->codec_id);
        if (!decoder) {
            throw std::runtime_error("Could not find decoder");
        }

        codecContext = avcodec_alloc_context3(decoder);
        if (!codecContext) {
            throw std::runtime_error("Could not allocate codec context");
        }

        if (avcodec_parameters_to_context(codecContext, formatContext->streams[audioStreamIndex]->codecpar) < 0) {
            throw std::runtime_error("Could not copy codec parameters to context");
        }

        if (avcodec_open2(codecContext, decoder, nullptr) < 0) {
            throw std::runtime_error("Could not open codec");
        }

        // 4. Resampler Setup (Demucs requirements: 44100Hz, Stereo, FLTP)
        swrContext = swr_alloc();
        if (!swrContext) {
            throw std::runtime_error("Could not allocate SwrContext");
        }

        AVChannelLayout out_ch_layout = AV_CHANNEL_LAYOUT_STEREO;
        av_opt_set_chlayout(swrContext, "out_chlayout", &out_ch_layout, 0);
        av_opt_set_int(swrContext, "out_sample_rate", 44100, 0);
        av_opt_set_sample_fmt(swrContext, "out_sample_fmt", AV_SAMPLE_FMT_FLTP, 0);

        av_opt_set_chlayout(swrContext, "in_chlayout", &codecContext->ch_layout, 0);
        av_opt_set_int(swrContext, "in_sample_rate", codecContext->sample_rate, 0);
        av_opt_set_sample_fmt(swrContext, "in_sample_fmt", codecContext->sample_fmt, 0);

        if (swr_init(swrContext) < 0) {
            throw std::runtime_error("Could not initialize SwrContext");
        }

        packet = av_packet_alloc();
        frame = av_frame_alloc();

        if (av_samples_alloc_array_and_samples(&out_data, nullptr, 2, max_out_samples, AV_SAMPLE_FMT_FLTP, 0) < 0) {
            throw std::runtime_error("Could not allocate output samples");
        }

        // 5. Decoding Loop
        auto process_frame = [&]() {
            int out_samples = av_rescale_rnd(swr_get_delay(swrContext, codecContext->sample_rate) + frame->nb_samples, 44100, codecContext->sample_rate, AV_ROUND_UP);
            if (out_samples > max_out_samples) {
                av_freep(&out_data[0]);
                av_freep(&out_data);
                max_out_samples = out_samples;
                if (av_samples_alloc_array_and_samples(&out_data, nullptr, 2, max_out_samples, AV_SAMPLE_FMT_FLTP, 0) < 0) {
                    throw std::runtime_error("Could not reallocate output samples");
                }
            }

            int converted = swr_convert(swrContext, out_data, out_samples, (const uint8_t**)frame->data, frame->nb_samples);
            if (converted > 0) {
                float* left = (float*)out_data[0];
                float* right = (float*)out_data[1];
                for (int i = 0; i < converted; i++) {
                    leftBuffer.push_back(left[i]);
                    rightBuffer.push_back(right[i]);
                }
            }
        };

        while (av_read_frame(formatContext, packet) >= 0) {
            if (packet->stream_index == audioStreamIndex) {
                if (avcodec_send_packet(codecContext, packet) == 0) {
                    while (avcodec_receive_frame(codecContext, frame) == 0) {
                        process_frame();
                    }
                }
            }
            av_packet_unref(packet);
        }

        // Flush Decoder
        avcodec_send_packet(codecContext, nullptr);
        while (avcodec_receive_frame(codecContext, frame) == 0) {
            process_frame();
        }

        // Flush Resampler
        int converted = swr_convert(swrContext, out_data, max_out_samples, nullptr, 0);
        if (converted > 0) {
            float* left = (float*)out_data[0];
            float* right = (float*)out_data[1];
            for (int i = 0; i < converted; i++) {
                leftBuffer.push_back(left[i]);
                rightBuffer.push_back(right[i]);
            }
        }

        cleanup();

        // 6. Tensor Formatting (Planar: All Left then All Right)
        std::vector<float> result = std::move(leftBuffer);
        result.insert(result.end(), rightBuffer.begin(), rightBuffer.end());
        return result;

    } catch (...) {
        cleanup();
        throw;
    }
}
