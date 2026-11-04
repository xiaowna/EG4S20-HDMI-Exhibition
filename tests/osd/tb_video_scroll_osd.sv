`timescale 1ns/1ps

module tb_video_scroll_osd;
    localparam [23:0] BG     = 24'h80_40_20;
    localparam [23:0] DIM_BG = 24'h40_20_10;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg de = 1'b0;
    reg vsync = 1'b1;
    reg [23:0] rgb = BG;
    reg [2:0] image_count = 0;
    reg [1:0] image_index = 0;
    reg paused = 0, wav_found = 0, catalog_ready = 0, image_valid = 0;
    wire [23:0] rgb_out;

    video_scroll_osd dut (.image_valid(image_valid),
        .clk(clk), .rst_n(rst_n), .de(de), .vsync(vsync),
        .image_count(image_count), .image_index(image_index),
        .paused(paused), .wav_found(wav_found), .catalog_ready(catalog_ready),
        .rgb(rgb), .rgb_out(rgb_out)
    );

    reg [639:0] frame_a_glyph [0:15];
    integer glyph_a_count = 0;
    integer glyph_b_count = 0;
    integer first_char_count = 0;
    integer min_glyph_x = 640;

    // Independent, character-based pixel oracle; each byte is one 8-pixel row.
    function [7:0] expected_row(input [7:0] letter, input integer row);
        reg [63:0] bitmap;
        begin
            case (letter)
                "k": bitmap = 64'h4040444870484400;
                "s": bitmap = 64'h00003c4038047800;
                "b": bitmap = 64'h4040784444447800;
                "l": bitmap = 64'h3010101010103800;
                ",": bitmap = 64'h0000000000181810;
                "z": bitmap = 64'h00007c0810207c00;
                "d": bitmap = 64'h04043c4444443c00;
                "j": bitmap = 64'h0800180808483000;
                "I": bitmap = 64'h3c18181818183c00;
                "M": bitmap = 64'h42665a4242424200;
                "G": bitmap = 64'h3c42404e42423c00;
                "0": bitmap = 64'h3c42464a52623c00;
                "2": bitmap = 64'h3c42020c30407e00;
                "3": bitmap = 64'h3c42021c02423c00;
                "4": bitmap = 64'h0c1424447e040400;
                "/": bitmap = 64'h0204040810102000;
                "P": bitmap = 64'h7c42427c40404000;
                "L": bitmap = 64'h4040404040407e00;
                "A": bitmap = 64'h3c42427e42424200;
                "Y": bitmap = 64'h4242241818181800;
                "U": bitmap = 64'h4242424242423c00;
                "S": bitmap = 64'h3e40403c02027c00;
                "E": bitmap = 64'h7e40407c40407e00;
                "W": bitmap = 64'h42425a5a66664200;
                "V": bitmap = 64'h4242422424181800;
                "T": bitmap = 64'h7e18181818181800;
                "O": bitmap = 64'h3c42424242423c00;
                "N": bitmap = 64'h4262524a46424200;
                default: bitmap = 0;
            endcase
            expected_row = bitmap[63-row*8 -: 8];
        end
    endfunction

    function expected_caption(input integer x, input integer y, input integer scroll_value);
        reg [127:0] caption;
        reg [7:0] pixels, letter;
        integer text_position;
        begin
            caption = "kskbl,zdjd      ";
            text_position = x + scroll_value - 640;
            expected_caption = 0;
            if (y >= 32 && y < 48 && text_position >= 0 && text_position < 256) begin
                letter = caption[127-(text_position/16)*8 -: 8];
                pixels = expected_row(letter, (y-32)/2);
                expected_caption = pixels[7-(text_position%16)/2];
            end
        end
    endfunction

    function is_yellow(input [23:0] color);
        begin
            is_yellow = color == 24'hf0b877;
        end
    endfunction

    // Exactly one active-low frame pulse; scroll must advance only once.
    task pulse_vsync;
        begin
            @(negedge clk); vsync = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk); vsync = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    // mode 0: initial off-screen text; 1: capture; 2: compare a 4-pixel
    // leftward move; 3: confirm the first character reaches the left edge.
    task scan_frame(input integer mode, input integer scroll_value);
        integer y, x, row;
        reg yellow_pixel;
        reg shifted_pixel;
        begin
            for (y = 0; y <= 56; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    @(negedge clk);
                    de = 1'b1;
                    rgb = BG;
                    #1;
                    yellow_pixel = is_yellow(rgb_out);
                    if (yellow_pixel !== expected_caption(x, y, scroll_value))
                        $fatal(1, "caption pixel mismatch: mode=%0d y=%0d x=%0d", mode, y, x);
                    if (y < 24 || y > 55) begin
                        if (rgb_out !== BG)
                            $fatal(1, "outside band changed: mode=%0d y=%0d x=%0d rgb=%h", mode, y, x, rgb_out);
                    end else if (y < 32 || y > 47) begin
                        if (rgb_out !== DIM_BG)
                            $fatal(1, "dim band mismatch: mode=%0d y=%0d x=%0d rgb=%h", mode, y, x, rgb_out);
                    end else begin
                        if (!yellow_pixel && rgb_out !== DIM_BG)
                            $fatal(1, "text band has unexpected color: mode=%0d y=%0d x=%0d rgb=%h", mode, y, x, rgb_out);
                        row = y - 32;
                        if (mode == 0 && yellow_pixel)
                            $fatal(1, "text visible before scrolling: y=%0d x=%0d", y, x);
                        if (mode == 1) begin
                            frame_a_glyph[row][x] = yellow_pixel;
                            if (yellow_pixel) begin
                                glyph_a_count = glyph_a_count + 1;
                                if (x < min_glyph_x) min_glyph_x = x;
                            end
                        end
                        if (mode == 2) begin
                            shifted_pixel = (x + 4 < 640) ? frame_a_glyph[row][x + 4] : 1'b0;
                            if (yellow_pixel !== shifted_pixel)
                                $fatal(1, "scroll is not 4 pixels/frame: y=%0d x=%0d", y, x);
                            if (yellow_pixel) glyph_b_count = glyph_b_count + 1;
                        end
                        if (mode == 3 && x < 16 && yellow_pixel)
                            first_char_count = first_char_count + 1;
                    end
                    @(posedge clk); #1;
                end
                @(negedge clk); de = 1'b0;
                @(posedge clk); #1;
            end
        end
    endtask

    // Check every doubled pixel of the existing status line, plus its dim band.
    task check_status(input [143:0] label_text);
        integer x, y, slot;
        reg [7:0] pixels, letter;
        reg [23:0] expected;
        begin
            for (y = 432; y < 464; y = y + 1) begin
                for (x = 0; x < 640; x = x + 1) begin
                    @(negedge clk);
                    de = 1;
                    dut.active_x = x;
                    dut.active_y = y;
                    expected = DIM_BG;
                    if (x >= 16 && x < 304 && y >= 440 && y < 456) begin
                        slot = (x-16)/16;
                        letter = label_text[143-slot*8 -: 8];
                        pixels = expected_row(letter, (y-440)/2);
                        if (pixels[7-((x-16)%16)/2]) expected = 24'hb6e7d7;
                    end
                    #1;
                    if (rgb_out !== expected)
                        $fatal(1, "status pixel mismatch: y=%0d x=%0d rgb=%h expected=%h", y, x, rgb_out, expected);
                end
            end
            @(negedge clk); de = 0;
            #1;
            if (rgb_out !== BG) $fatal(1, "blanking changed source RGB");
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        scan_frame(0, 0); // scroll = 0, text starts at x = 640
        for (i = 0; i < 140; i = i + 1) pulse_vsync();
        scan_frame(1, 560); // scroll = 560, text starts near x = 80
        if (glyph_a_count < 10 || min_glyph_x < 70 || min_glyph_x > 100)
            $fatal(1, "text not visible near expected x: pixels=%0d min_x=%0d", glyph_a_count, min_glyph_x);

        pulse_vsync();
        scan_frame(2, 564); // scroll = 564, same glyphs moved left by 4
        if (glyph_b_count != glyph_a_count)
            $fatal(1, "glyph count changed without clipping: %0d vs %0d", glyph_b_count, glyph_a_count);

        for (i = 0; i < 19; i = i + 1) pulse_vsync();
        scan_frame(3, 640); // scroll = 640, the first 'k' is at x = 0..15
        if (first_char_count == 0)
            $fatal(1, "first character did not reach x = 0..15");

        image_valid = 1; image_count = 4; image_index = 1;
        wav_found = 1; catalog_ready = 1;
        pulse_vsync();
        check_status("IMG 2/4 PLAY  WAV ");
        paused = 1; image_count = 3; image_index = 2;
        pulse_vsync();
        check_status("IMG 3/3 PAUSE WAV ");
        paused = 0; image_count = 4; image_index = 3; wav_found = 0;
        pulse_vsync();
        check_status("IMG 4/4 PLAY  TONE");
        image_valid = 0; image_count = 0; catalog_ready = 0;
        pulse_vsync();
        check_status("IMG 0/0 PLAY  WAIT");

        $display("PASS video_scroll_osd: exact lowercase kskbl,zdjd pixels, 4-pixel scroll, dim/passthrough, PLAY/PAUSE/WAV/TONE/WAIT pixels");
        $finish;
    end
endmodule
