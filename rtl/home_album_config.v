// Generated static column descriptors; catalogue indices are zero-based.
module home_album_config #(parameter TOPIC_FOLDERS=0)(input wire [2:0] index,output wire [4:0] first_image,
 output wire [5:0] image_limit,output wire [1:0] music_index,input wire [24:0] folder_info);
 localparam [24:0] FIRST=25'h00930c0;
 localparam [29:0] LIMIT=30'h06612306;
 localparam [9:0] MUSIC=10'h0e4;
 wire folders=TOPIC_FOLDERS&&folder_info[24]&&index<4;
 wire [5:0] folder_first=(index==0)?6'd0:((index==1)?folder_info[5:0]:((index==2)?folder_info[11:6]:folder_info[17:12]));
 wire [5:0] folder_end=(index==0)?folder_info[5:0]:((index==1)?folder_info[11:6]:((index==2)?folder_info[17:12]:folder_info[23:18]));
 assign first_image=folders?folder_first[4:0]:FIRST[index*5+:5];
 assign image_limit=folders?folder_end:LIMIT[index*6+:6];
 assign music_index=MUSIC[index*2+:2];
endmodule
