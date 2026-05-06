#include "AudioEncoder.h"
#include <iostream>

void AudioEncoder::encode(const std::vector<float>& planarAudio, const std::string& outputPath) {
    if (planarAudio.empty() || planarAudio.size() % 2 != 0) {
        throw std::invalid_argument("Input audio must be non-empty and have an even number of samples (stereo planar).");
    }

    AVFormatContext* formatContext = nullptr;
    AVCodecContext* codecContext = nullptr;
    SwrContext* swrContext = nullptr;
    AVFrame* inFrame = nullptr;
    AVFrame* outFrame = nullptr;
    AVPacket* packet = nullptr;
    AVStream* stream = nullptr;

    auto cleanup = [&]() {
        if (packet) av_packet_free(&packet);
        if (inFrame) av_frame_free(&inFrame);
        if (outFrame) av_frame_free(&outFrame);
        if (swrContext) swr_free(&swrContext);
        if (codecContext) avcodec_free_context(&codecContext);
        if (formatContext) {
            if (!(formatContext->oformat->flags & AVFMT_NOFILE)) {
                avio_closep(&formatContext->pb);
            }
            avformat_free_context(formatContext);
        }
    };

    try {
        // 1. Initialization
        if (avformat_alloc_output_context2(&formatContext, nullptr, "wav", outputPath.c_str()) < 0) {
            throw std::runtime_error("Could not allocate output context for: " + outputPath);
        }

        const AVCodec* encoder = avcodec_find_encoder(AV_CODEC_ID_PCM_S16LE);
        if (!encoder) {
            throw std::runtime_error("Could not find PCM S16LE encoder");
        }

        stream = avformat_new_stream(formatContext, nullptr);
        if (!stream) {
            throw std::runtime_error("Could not create new stream");
        }

        codecContext = avcodec_alloc_context3(encoder);
        if (!codecContext) {
            throw std::runtime_error("Could not allocate codec context");
        }

        // 2. Codec Setup (44100Hz, Stereo, S16 Interleaved)
        AVChannelLayout ch_layout = AV_CHANNEL_LAYOUT_STEREO;
        codecContext->sample_rate = 44100;
        av_channel_layout_copy(&codecContext->ch_layout, &ch_layout);
        codecContext->sample_fmt = AV_SAMPLE_FMT_S16;
        codecContext->time_base = (AVRational){1, 44100};

        if (formatContext->oformat->flags & AVFMT_GLOBALHEADER) {
            codecContext->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
        }

        if (avcodec_open2(codecContext, encoder, nullptr) < 0) {
            throw std::runtime_error("Could not open encoder");
        }

        if (avcodec_parameters_from_context(stream->codecpar, codecContext) < 0) {
            throw std::runtime_error("Could not copy codec parameters to stream");
        }

        // 3. Resampler Setup (FLTP -> S16)
        swrContext = swr_alloc();
        av_opt_set_chlayout(swrContext, "in_chlayout", &ch_layout, 0);
        av_opt_set_int(swrContext, "in_sample_rate", 44100, 0);
        av_opt_set_sample_fmt(swrContext, "in_sample_fmt", AV_SAMPLE_FMT_FLTP, 0);

        av_opt_set_chlayout(swrContext, "out_chlayout", &ch_layout, 0);
        av_opt_set_int(swrContext, "out_sample_rate", 44100, 0);
        av_opt_set_sample_fmt(swrContext, "out_sample_fmt", AV_SAMPLE_FMT_S16, 0);

        if (swr_init(swrContext) < 0) {
            throw std::runtime_error("Could not initialize resampler");
        }

        // 4. File Writing Header
        if (!(formatContext->oformat->flags & AVFMT_NOFILE)) {
            if (avio_open(&formatContext->pb, outputPath.c_str(), AVIO_FLAG_WRITE) < 0) {
                throw std::runtime_error("Could not open output file: " + outputPath);
            }
        }

        if (avformat_write_header(formatContext, nullptr) < 0) {
            throw std::runtime_error("Could not write header");
        }

        // 5. Encoding Loop
        int64_t total_samples_per_channel = planarAudio.size() / 2;
        int frame_size = 1024;
        inFrame = av_frame_alloc();
        outFrame = av_frame_alloc();
        packet = av_packet_alloc();

        inFrame->nb_samples = frame_size;
        inFrame->format = AV_SAMPLE_FMT_FLTP;
        av_channel_layout_copy(&inFrame->ch_layout, &ch_layout);

        outFrame->nb_samples = frame_size;
        outFrame->format = AV_SAMPLE_FMT_S16;
        av_channel_layout_copy(&outFrame->ch_layout, &ch_layout);

        if (av_frame_get_buffer(outFrame, 0) < 0) {
            throw std::runtime_error("Could not allocate output frame buffer");
        }

        int64_t pts = 0;
        for (int64_t offset = 0; offset < total_samples_per_channel; offset += frame_size) {
            int current_nb_samples = std::min((int64_t)frame_size, total_samples_per_channel - offset);
            
            inFrame->nb_samples = current_nb_samples;
            inFrame->data[0] = (uint8_t*)(planarAudio.data() + offset);
            inFrame->data[1] = (uint8_t*)(planarAudio.data() + total_samples_per_channel + offset);

            outFrame->nb_samples = current_nb_samples;
            if (swr_convert(swrContext, outFrame->data, current_nb_samples, (const uint8_t**)inFrame->data, current_nb_samples) < 0) {
                throw std::runtime_error("Error during resampling");
            }

            outFrame->pts = pts;
            pts += current_nb_samples;

            if (avcodec_send_frame(codecContext, outFrame) == 0) {
                while (avcodec_receive_packet(codecContext, packet) == 0) {
                    av_packet_rescale_ts(packet, codecContext->time_base, stream->time_base);
                    packet->stream_index = stream->index;
                    av_interleaved_write_frame(formatContext, packet);
                    av_packet_unref(packet);
                }
            }
        }

        // Flush
        avcodec_send_frame(codecContext, nullptr);
        while (avcodec_receive_packet(codecContext, packet) == 0) {
            av_packet_rescale_ts(packet, codecContext->time_base, stream->time_base);
            packet->stream_index = stream->index;
            av_interleaved_write_frame(formatContext, packet);
            av_packet_unref(packet);
        }

        av_write_trailer(formatContext);
        cleanup();

    } catch (...) {
        cleanup();
        throw;
    }
}
