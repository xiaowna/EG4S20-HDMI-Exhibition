// Solar and Earth-Moon share the orbit projector and solid sphere rasterizer.
// Render during vertical blanking, in back-to-front order.
// A shared 128x128 canvas is displayed 3x at x=16,y=48; sidebar is separate.
// Orbit radii/body sizes are deliberately not to physical scale.
// yaw: camera azimuth in 128 steps. pitch={4-bit elevation,3-bit speed}.
module video_scene3d(
 input wire sys_clk,pix_clk,rst_n,enable,
 input wire [6:0] yaw,pitch,
 input wire scene_mode,input wire [1:0] zoom,
 input wire de,vsync,input wire [9:0] x,y,
 output reg [23:0] rgb_out,output reg valid_out,
 output reg ready,output reg fault);
 localparam IDLE=0,CLEAR=1,UPDATE=2,GEOM_X=3,GEOM_Z=4,GEOM_Y=5,
  ORBIT_X=6,ORBIT_Z=7,ORBIT_Y=8,ORBIT_WRITE=9,FIND=10,OBJECT=11,
  SPHERE_INIT=12,RING_X=13,RING_Y=14,RING_WRITE=15,PHASE_READ=16,
  SPHERE_ROW=17,SPHERE_PIXEL=18,OBJECT_DONE=30,RING_Z=31;
 localparam integer DRAW_LIMIT=45000;
 reg [5:0] state;
 reg [13:0] clear_address;
 reg [15:0] budget;
 (* async_reg="true" *) reg vs1,vs2,de1,de2;
 reg vs_prev;
 wire frame_tick=vs_prev&&!vs2;
 reg [2:0] speed_q;reg [3:0] planet;
 reg scene_q;reg [1:0] zoom_q;
 reg [6:0] azimuth_q;reg [3:0] elevation_q;
 // Nine 24-bit phases use synchronous eRAM, with one shared accumulator.
 // Initialization is serialized at the first frame instead of resetting RAM.
 wire [23:0] phase_read;reg [23:0] phase_next;reg phase_initialized;
 function [23:0] initial_phase;
  input [3:0] n;
  begin case(n)
   0:initial_phase=24'h680000;1:initial_phase=24'hd80000;
   2:initial_phase=24'h080000;3:initial_phase=24'hba0000;
   4:initial_phase=24'h3c0000;5:initial_phase=24'h8c0000;
   6:initial_phase=24'hf00000;7:initial_phase=24'h6a0000;default:initial_phase=24'h200000;
  endcase end
 endfunction
 reg [6:0] vx[0:9],vy[0:9];
 reg signed [7:0] vz[0:9];
 reg signed [7:0] projected_z;
 reg [6:0] orbit_angle;
 reg [6:0] orbit_x,orbit_y;
 reg [9:0] drawn;
 reg [3:0] scan_index,best_index,object_index;
 reg signed [7:0] best_depth;
 reg signed [5:0] line_x,line_y;
 reg [4:0] radius;
 reg [9:0] radius_squared,row_squared;
 reg [10:0] distance_squared;
 reg [4:0] shade_base;
 reg light_left,light_above;
 reg [4:0] ring_step;
 reg ring_front;
 reg signed [7:0] ring_x,ring_y;

 function signed [7:0] sine;
  input [6:0] angle;reg [5:0] a;reg [7:0] v;
  begin
   a=angle[5]?(6'd32-{1'b0,angle[4:0]}):{1'b0,angle[4:0]};
   case(a)
    0:v=0;1:v=6;2:v=12;3:v=19;4:v=25;5:v=31;6:v=37;7:v=43;
    8:v=49;9:v=54;10:v=60;11:v=65;12:v=71;13:v=76;14:v=81;15:v=85;
    16:v=90;17:v=94;18:v=98;19:v=102;20:v=106;21:v=109;22:v=112;23:v=115;
    24:v=117;25:v=120;26:v=122;27:v=123;28:v=125;29:v=126;30:v=126;31:v=127;
    default:v=127;
   endcase
   sine=angle[6]?-$signed(v):$signed(v);
  end
 endfunction
 function [5:0] orbital_radius;
  input [2:0] n;input [1:0] level;reg [17:0] radii;
  begin
   // Leave room for the outer bodies while all eight orbits grow at zoom 2.
   case(n)
    0:radii={6'd11,6'd14,6'd16}; 1:radii={6'd16,6'd19,6'd21};
    2:radii={6'd20,6'd23,6'd25}; 3:radii={6'd24,6'd29,6'd31};
    4:radii={6'd30,6'd35,6'd38}; 5:radii={6'd36,6'd41,6'd44};
    6:radii={6'd41,6'd46,6'd49}; default:radii={6'd45,6'd50,6'd52};
   endcase
   orbital_radius=(level==0)?radii[17:12]:((level==2)?radii[5:0]:radii[11:6]);
  end
 endfunction
 // One simulated day is 0.1 s at the nominal 59.52 Hz board frame rate.
 // Ratios use mean sidereal periods; integer Q24 increments retain Neptune's
 // motion even at 0.1x. The starting angles are an illustrative arrangement.
 function [15:0] orbital_step;
  input [2:0] n;
  begin case(n)
   0:orbital_step=32040;1:orbital_step=12543;2:orbital_step=7715;3:orbital_step=4102;
   4:orbital_step=650;5:orbital_step=262;6:orbital_step=92;default:orbital_step=47;
  endcase end
 endfunction
 function [11:0] slow_step;
  input [2:0] n;
  begin case(n)
   0:slow_step=3204;1:slow_step=1254;2:slow_step=772;3:slow_step=410;
   4:slow_step=65;5:slow_step=26;6:slow_step=9;default:slow_step=5;
  endcase end
 endfunction
 wire [16:0] base_step=(planet==8)?17'd103162:{1'b0,orbital_step(planet[2:0])};
 wire [13:0] slow_base=(planet==8)?14'd10316:{2'd0,slow_step(planet[2:0])};
 reg [19:0] phase_step;
 always @*begin
  case(speed_q)
   0:phase_step={6'd0,slow_base};
   1:phase_step={5'd0,base_step[16:2]};
   2:phase_step={4'd0,base_step[16:1]};
   3:phase_step={3'd0,base_step};
   4:phase_step={2'd0,base_step,1'd0};
   5:phase_step={1'd0,base_step,2'd0};
   6:phase_step={base_step,3'd0};
   default:phase_step={base_step,3'd0}+{2'd0,base_step,1'd0};
  endcase
 end
 function [3:0] body_radius;
  input [3:0] n;input [1:0] level;reg [3:0] normal_radius;
  begin
   case(n)
    0,3:normal_radius=4;1,7:normal_radius=5;2,6:normal_radius=6;
    4:normal_radius=8;5:normal_radius=7;default:normal_radius=8;
   endcase
   body_radius=(level==0)?normal_radius-4'd1:
    ((level==2)?((n==7)?4'd9:normal_radius+4'd2):normal_radius);
  end
 endfunction
 function [4:0] body_color;
  input [3:0] n;
  begin case(n)
   0:body_color=2;1:body_color=5;2:body_color=8;3:body_color=11;
   4:body_color=14;5:body_color=17;6:body_color=20;7:body_color=23;
   8:body_color=26;default:body_color=29;
  endcase end
 endfunction
 // Scan the bounding square with first differences. If x advances by one,
 // x^2 advances by 2*x+1; the same recurrence initializes each row.
 wire [10:0] next_distance=distance_squared+{{4{line_x[5]}},line_x,1'b1};
 wire [9:0] next_row_squared=row_squared+{{3{line_y[5]}},line_y,1'b1};
 wire signed [6:0] light_x=light_left?-$signed({line_x[5],line_x}):$signed({line_x[5],line_x});
 wire signed [6:0] light_y=light_above?-$signed({line_y[5],line_y}):$signed({line_y[5],line_y});
 wire signed [6:0] light=light_x+light_y;
 wire signed [6:0] terminator=$signed({3'b000,radius[4:1]});
 wire dark=light< -terminator||(distance_squared>({1'b0,radius_squared}-{3'b0,radius_squared[9:2]})&&light<0);
 wire lit=light>terminator;
 // Muted color accents sit inside the silhouette instead of tracing a grid.
 wire signed [6:0] coast=$signed({line_x[5],line_x})+($signed({line_y[5],line_y})>>>1);
 wire earth_land=object_index==2&&
  ((line_y<0&&coast<=-2&&coast>= -terminator-7'sd3)||
   (line_y>=0&&line_y<$signed({2'b0,radius[4:1]})&&coast>=2&&coast<=terminator+7'sd2));
 wire jupiter_band=object_index==4&&(line_y==-2||line_y==2||line_y==3);
 wire [1:0] shade=dark?2'd0:((lit&&!jupiter_band)?2'd2:2'd1);
 wire [4:0] sphere_pixel=earth_land&&!dark?5'd21:shade_base+{3'b0,shade};
 wire [5:0] moon_orbit=(zoom_q==0)?6'd32:((zoom_q==2)?6'd48:6'd40);
 wire [4:0] earth_radius=(zoom_q==0)?5'd14:((zoom_q==2)?5'd22:5'd18);
 wire [4:0] moon_radius=(zoom_q==0)?5'd6:((zoom_q==2)?5'd10:5'd8);
 wire signed [7:0] ring_radius=(zoom_q==0)?8'sd10:((zoom_q==2)?8'sd15:8'sd12);
 wire [5:0] active_orbit=(planet==8)?moon_orbit:orbital_radius(planet[2:0],zoom_q);
 wire [3:0] geom_index=(planet==8)?4'd9:planet;
 reg signed [7:0] operand;
 reg [6:0] angle;
 always @*begin
  operand=$signed({2'b0,active_orbit});
  angle=phase_next[23:17]+azimuth_q+7'd32;
  case(state)
   GEOM_Z:angle=phase_next[23:17]+azimuth_q;
   GEOM_Y,ORBIT_Y:begin operand=projected_z;angle={2'b00,elevation_q,1'b0};end
   ORBIT_X:angle=orbit_angle+7'd32;
   ORBIT_Z:angle=orbit_angle;
   RING_X:begin operand=ring_radius;angle={ring_front?1'b0:1'b1,ring_step,1'b0}+7'd32;end
   RING_Z:begin operand=ring_radius;angle={ring_front?1'b0:1'b1,ring_step,1'b0};end
   RING_Y:begin operand=projected_z;angle={2'b00,elevation_q,1'b0};end
   SPHERE_INIT:operand=$signed({3'd0,radius});
   default:;
  endcase
 end
 reg signed [7:0] coefficient;
 always @*begin
  coefficient=(state==SPHERE_INIT)?$signed({3'd0,radius}):sine(angle);
 end
 // Register the DSP inputs and result, separating lookup, multiply and RAM
 // write into three clock stages. Every math state consumes only a fresh result.
 reg signed [7:0] operand_q,coefficient_q;
 reg signed [15:0] product;
 always @(posedge sys_clk)begin operand_q<=operand;coefficient_q<=coefficient;product<=operand_q*coefficient_q;end
 reg [1:0] math_wait;
 wire math_ready=math_wait==2;
 wire math_state=(state>=GEOM_X&&state<=ORBIT_Y)||
  state==RING_X||state==RING_Y||state==RING_Z||state==SPHERE_INIT;
 wire signed [8:0] body_x=$signed({2'b0,vx[object_index]})+$signed(line_x);
 wire signed [8:0] body_y=$signed({2'b0,vy[object_index]})+$signed(line_y);
 wire signed [8:0] ring_px=$signed({2'b0,vx[5]})+$signed(ring_x);
 wire signed [8:0] ring_py=$signed({2'b0,vy[5]})+$signed(ring_y);
 wire can_write=budget<DRAW_LIMIT&&!de2&&!frame_tick;
 wire body_in_bounds=body_x>=0&&body_x<128&&body_y>=0&&body_y<128;
 wire ring_in_bounds=ring_px>=0&&ring_px<128&&ring_py>=0&&ring_py<128;
 wire writing=can_write&&(state==CLEAR||state==ORBIT_WRITE||
  (state==SPHERE_PIXEL&&body_in_bounds&&distance_squared<={1'b0,radius_squared})||(state==RING_WRITE&&ring_in_bounds));
 wire [13:0] write_address=(state==CLEAR)?clear_address:
  ((state==ORBIT_WRITE)?{orbit_y,orbit_x}:((state==RING_WRITE)?{ring_py[6:0],ring_px[6:0]}:{body_y[6:0],body_x[6:0]}));
 wire [4:0] write_data=(state==CLEAR)?5'd0:((state==ORBIT_WRITE)?5'd1:
  ((state==RING_WRITE)?(ring_front?5'd19:5'd17):sphere_pixel));
 (* ram_style="bram" *) reg [4:0] canvas[0:16383];
 reg [4:0] read_pixel;
 wire [9:0] local_x=x-10'd16,local_y=y-10'd48;
 // Radix-8 division by three: each five-input digit table fits a LUT5.
 // Returning the remainder also removes separate font subpixel arithmetic.
 function [4:0] divide3_digit;
  input [4:0] value;
  begin case(value)
   0:divide3_digit=0;1:divide3_digit=1;2:divide3_digit=2;
   3:divide3_digit=4;4:divide3_digit=5;5:divide3_digit=6;
   6:divide3_digit=8;7:divide3_digit=9;8:divide3_digit=10;
   9:divide3_digit=12;10:divide3_digit=13;11:divide3_digit=14;
   12:divide3_digit=16;13:divide3_digit=17;14:divide3_digit=18;
   15:divide3_digit=20;16:divide3_digit=21;17:divide3_digit=22;
   18:divide3_digit=24;19:divide3_digit=25;20:divide3_digit=26;
   21:divide3_digit=28;22:divide3_digit=29;23:divide3_digit=30;
   default:divide3_digit=0;
  endcase end
 endfunction
 function [8:0] canvas_divmod3;
  input [9:0] value;reg [4:0] a,b,c;
  begin
   a=divide3_digit({1'b0,value[9:6]});
   b=divide3_digit({a[1:0],value[5:3]});
   c=divide3_digit({b[1:0],value[2:0]});
   canvas_divmod3={a[2],b[4:2],c[4:2],c[1:0]};
  end
 endfunction
 wire [8:0] divmod_x=canvas_divmod3(local_x),divmod_y=canvas_divmod3(local_y);
 wire [6:0] canvas_x=divmod_x[8:2],canvas_y=divmod_y[8:2];
 wire [13:0] read_address={canvas_y,canvas_x};
 always @(posedge sys_clk)if(writing)canvas[write_address]<=write_data;
 solar_phase_ram phases(.clk(sys_clk),.address({5'd0,planet}),.write_enable(state==GEOM_X&&math_ready&&can_write),
  .write_data(phase_next),.read_data(phase_read));
 always @(posedge pix_clk)read_pixel<=canvas[read_address];
 integer i;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;clear_address<=0;budget<=0;ready<=0;fault<=0;math_wait<=0;
   vs1<=1;vs2<=1;vs_prev<=1;de1<=0;de2<=0;speed_q<=3;azimuth_q<=12;elevation_q<=10;planet<=0;scene_q<=0;zoom_q<=1;
   projected_z<=0;orbit_angle<=0;orbit_x<=0;orbit_y<=0;drawn<=0;
   scan_index<=0;best_index<=0;object_index<=0;best_depth<=127;
   line_x<=0;line_y<=0;radius<=0;ring_step<=0;ring_front<=0;ring_x<=0;ring_y<=0;
   phase_next<=0;phase_initialized<=0;
   radius_squared<=0;row_squared<=0;distance_squared<=0;
   shade_base<=0;light_left<=0;light_above<=0;
   for(i=0;i<10;i=i+1)begin vx[i]<=64;vy[i]<=64;vz[i]<=0;end
  end else begin
   vs1<=vsync;vs2<=vs1;vs_prev<=vs2;de1<=de;de2<=de1;
   if(state!=IDLE)budget<=budget+1'b1;
   if(frame_tick)begin
    if(state!=IDLE)fault<=1;
    state<=CLEAR;clear_address<=0;budget<=0;ready<=0;speed_q<=pitch[2:0];azimuth_q<=yaw;elevation_q<=pitch[6:3];
    scene_q<=scene_mode;zoom_q<=zoom;math_wait<=0;
   end else if(state!=IDLE&&(budget>=DRAW_LIMIT||de2))begin
    state<=IDLE;ready<=0;fault<=1;math_wait<=0;
   end else if(math_state&&!math_ready)math_wait<=math_wait+1'b1;
   else begin
    math_wait<=0;
    case(state)
    CLEAR:begin
     if(clear_address==16383)begin planet<=0;state<=PHASE_READ;end
     else clear_address<=clear_address+1'b1;
    end
    PHASE_READ:state<=UPDATE;
    UPDATE:begin
     phase_next<=(phase_initialized?phase_read:initial_phase(planet))+(enable?{4'd0,phase_step}:24'd0);
     state<=GEOM_X;
    end
    GEOM_X:begin vx[geom_index]<=8'sd64+(product>>>7);state<=GEOM_Z;end
    GEOM_Z:begin projected_z<=product>>>7;vz[geom_index]<=product>>>7;state<=GEOM_Y;end
    GEOM_Y:begin
     vy[geom_index]<=8'sd64+(product>>>7);
     if(planet==8)begin
      phase_initialized<=1;planet<=scene_q?4'd8:4'd0;orbit_angle<=0;state<=ORBIT_X;
      if(scene_q)begin vx[2]<=64;vy[2]<=64;vz[2]<=0;end
     end
     else begin planet<=planet+1'b1;state<=PHASE_READ;end
    end
    ORBIT_X:begin orbit_x<=8'sd64+(product>>>7);state<=ORBIT_Z;end
    ORBIT_Z:begin projected_z<=product>>>7;state<=ORBIT_Y;end
    ORBIT_Y:begin orbit_y<=8'sd64+(product>>>7);state<=ORBIT_WRITE;end
    ORBIT_WRITE:begin
     if(orbit_angle==127)begin
      orbit_angle<=0;
      if(scene_q||planet==7)begin drawn<=scene_q?10'h1fb:10'h200;scan_index<=0;best_depth<=127;best_index<=0;state<=FIND;end
      else begin planet<=planet+1'b1;state<=ORBIT_X;end
     end else begin orbit_angle<=orbit_angle+1'b1;state<=ORBIT_X;end
    end
    FIND:begin
     if(!drawn[scan_index]&&$signed(vz[scan_index])<best_depth)begin
      best_depth<=vz[scan_index];best_index<=scan_index;
     end
     if(scan_index==9)state<=OBJECT;else scan_index<=scan_index+1'b1;
    end
    OBJECT:begin
     object_index<=best_index;
     radius<=scene_q?((best_index==2)?earth_radius:moon_radius):{1'b0,body_radius(best_index,zoom_q)};
     shade_base<=body_color(best_index);
     light_left<=vx[best_index]>=64;light_above<=vy[best_index]>=64;
     if(!scene_q&&best_index==5)begin ring_front<=0;ring_step<=0;state<=RING_X;end
     else state<=SPHERE_INIT;
    end
    SPHERE_INIT:begin
     radius_squared<=product[9:0];row_squared<=product[9:0];
     line_y<= -$signed({1'b0,radius});state<=SPHERE_ROW;
    end
    SPHERE_ROW:begin
     line_x<= -$signed({1'b0,radius});
     distance_squared<={1'b0,row_squared}+{1'b0,radius_squared};
     state<=SPHERE_PIXEL;
    end
    SPHERE_PIXEL:begin
     if(line_x==$signed({1'b0,radius}))begin
      if(line_y==$signed({1'b0,radius}))begin
       if(!scene_q&&object_index==5)begin ring_front<=1;ring_step<=0;state<=RING_X;end
       else state<=OBJECT_DONE;
      end else begin
       line_y<=line_y+1'b1;row_squared<=next_row_squared;state<=SPHERE_ROW;
      end
     end else begin
      line_x<=line_x+1'b1;distance_squared<=next_distance;
     end
    end
    OBJECT_DONE:begin
     drawn[object_index]<=1;
     if((drawn|(10'b1<<object_index))==10'h3ff)begin state<=IDLE;ready<=1;end
     else begin scan_index<=0;best_depth<=127;best_index<=0;state<=FIND;end
    end
    RING_X:begin ring_x<=product>>>7;state<=RING_Z;end
    RING_Z:begin projected_z<=product>>>7;state<=RING_Y;end
    RING_Y:begin ring_y<=product>>>7;state<=RING_WRITE;end
    RING_WRITE:begin
     if(ring_step==31)begin
      if(!ring_front)state<=SPHERE_INIT;else state<=OBJECT_DONE;
     end else begin ring_step<=ring_step+1'b1;state<=RING_X;end
    end
    default:;
    endcase
   end
  end
 end
 (* async_reg="true" *) reg [1:0] ready_sync,enable_sync;
 reg inside_q,de_q,valid_q,ready_prev,scene_pix;
 reg [1:0] zoom_pix;reg [2:0] speed_pix;
 reg panel_q,text_q,zoom_dot_q,zoom_focus_q;wire text_pixel;
 // Load coherent projected centers after a complete canvas arrives. Ten
 // blanking pixel clocks share one anchor calculator; centers stay unchanged
 // until the next frame, over 11000 system clocks after the worst render.
 // Anchors use native canvas coordinates; the existing /3 pixel coordinates
 // also locate 1x Chinese glyphs, avoiding ten extra pixel-scale comparators.
 reg [6:0] label_x[0:9],label_y[0:9];
 reg label_loading;reg [3:0] label_load_index;
 wire [6:0] load_center_x=vx[label_load_index],load_center_y=vy[label_load_index];
 wire [4:0] load_radius=scene_pix?((label_load_index==2)?earth_radius:moon_radius):
  {1'd0,body_radius(label_load_index,zoom_pix)};
 wire load_above=load_center_y<64||(!scene_pix&&label_load_index==8)||(scene_pix&&label_load_index==2);
 function [6:0] name_x;
  input [6:0] center;input wide;
  begin
   // Current orbit bounds keep every visible label inside the 128px canvas.
   // The independent geometry test checks this for every phase and zoom.
   name_x=center-(wide?7'd6:7'd4);
  end
 endfunction
 function [6:0] name_y;
  input [6:0] center;input [4:0] r;input above;
  reg [5:0] distance;
  reg [7:0] delta,position;
  begin
   distance={1'b0,r}+(above?6'd5:6'd2);
   delta={2'd0,distance}^{8{above}};
   position={1'b0,center}+delta+{7'd0,above};
   if(above&&position[7])name_y=0;
   else if(!above&&position>8'd124)name_y=124;
   else name_y=position[6:0];
  end
 endfunction
 wire [69:0] name_x_bus,name_y_bus;
 genvar name_slot;
 generate for(name_slot=0;name_slot<10;name_slot=name_slot+1)begin:name_bus
  assign name_x_bus[name_slot*7+:7]=label_x[name_slot];
  assign name_y_bus[name_slot*7+:7]=label_y[name_slot];
 end endgenerate
 wire line_font_request;wire [14:0] line_font_address;wire [1:0] line_name_pixel;
 reg [23:0] background_q;
 wire window=de&&x>=16&&x<400&&y>=48&&y<432;
 wire [9:0] star_hash=(x^{y[6:0],y[9:7]})+{y[4:0],y[9:5]};
 wire star=star_hash==10'd423&&x[1:0]!=0;
 wire frame_edge=((x==12||x==403)&&y>=44&&y<436)||((y==44||y==435)&&x>=12&&x<404);
 wire panel=de&&x>=432&&x<624&&((y>=104&&y<(scene_pix?232:344))||(y>=440&&y<464));
 wire text_window=de&&x>=464&&x<592&&y>=128&&y<(scene_pix?192:320);
 wire [6:0] text_x=x-10'd464;wire [7:0] text_y=y-10'd128;
 wire [7:0] text_row=scene_pix?{2'b11,text_y[5:0]}:text_y;
 // Keep the multiplier below the compact settings panel and its shadow.
 wire speed_window=de&&x>=464&&x<592&&y>=448&&y<456;
 wire [7:0] speed_row=8'd16+{1'b0,speed_pix,4'b0}+{3'b0,speed_pix,2'b0}+{5'b0,y[2:0]};
 function speed_atlas;
  input [5:0] row_group;
  begin case(row_group)
   4,5,9,10,14,15,19,20,24,25,29,30,34,35,39,40:speed_atlas=1;
   default:speed_atlas=0;
  endcase end
 endfunction
 wire zoom_dot=de&&scene_pix&&y>=208&&y<212&&x>=480&&x<560&&x[4:0]<16;
 wire [1:0] zoom_dot_index=(x-10'd480)>>5;
 // The two extra names occupy otherwise blank margins of the existing bank.
 // Hide those atlas cells in the fixed sidebar while reading them for labels.
 wire label_atlas=(text_row<12||(text_row>=192&&text_row<204))&&text_x<32;
 wire sidebar_read=speed_window||(text_window&&!label_atlas&&!speed_atlas(text_row[7:2]));
 scene_label_line_cache label_lines(.clk(pix_clk),.rst_n(rst_n),
  .enable(enable_sync[1]&&ready_sync[1]&&!label_loading),.scene_mode(scene_pix),.de(de),.x(x),.y(y),
  .anchors_x(name_x_bus),.anchors_y(name_y_bus),.font_available(!sidebar_read),
  .font_pixel(text_pixel),.font_request(line_font_request),.font_address(line_font_address),.name_pixel(line_name_pixel));
 scene_sidebar_rom sidebar(.clk(pix_clk),.address(line_font_request?line_font_address:{(speed_window?speed_row:text_row),text_x}),.pixel(text_pixel));
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   ready_sync<=0;enable_sync<=0;inside_q<=0;de_q<=0;valid_q<=0;background_q<=0;
   ready_prev<=0;scene_pix<=0;zoom_pix<=1;speed_pix<=3;panel_q<=0;text_q<=0;zoom_dot_q<=0;zoom_focus_q<=0;
   label_loading<=0;label_load_index<=0;
  end else begin
   ready_sync<={ready_sync[0],ready};enable_sync<={enable_sync[0],enable};
   ready_prev<=ready_sync[1];
   if(ready_sync[1]&&!ready_prev)begin
    scene_pix<=scene_q;zoom_pix<=zoom_q;speed_pix<=speed_q;label_loading<=1;label_load_index<=0;
   end else if(label_loading)begin
    label_x[label_load_index]<=name_x(load_center_x,label_load_index==6||label_load_index==7);
    label_y[label_load_index]<=name_y(load_center_y,load_radius,load_above);
    if(label_load_index==9)label_loading<=0;else label_load_index<=label_load_index+1'b1;
   end
   inside_q<=window;de_q<=de;valid_q<=enable_sync[1]&&ready_sync[1];
   panel_q<=panel;text_q<=sidebar_read;
   zoom_dot_q<=zoom_dot;zoom_focus_q<=zoom_dot_index==zoom_pix;
   background_q<=frame_edge?24'h3b5363:(star?24'h93a9b4:24'h0b1420);
  end
 end
 always @*begin
  valid_out=valid_q&&de_q;rgb_out=background_q;
  if(inside_q)case(read_pixel)
   1:rgb_out=24'h244456;
   2:rgb_out=24'h515961; 3:rgb_out=24'h8e9394; 4:rgb_out=24'hc9c8bf;
   5:rgb_out=24'h88603b; 6:rgb_out=24'hc89754; 7:rgb_out=24'heacb86;
   8:rgb_out=24'h243d66; 9:rgb_out=24'h417db0;10:rgb_out=24'h70bfe3;
   11:rgb_out=24'h733c39;12:rgb_out=24'hbc684e;13:rgb_out=24'he99068;
   14:rgb_out=24'h795645;15:rgb_out=24'hb58969;16:rgb_out=24'he3c39e;
   17:rgb_out=24'h8a704c;18:rgb_out=24'hc49c64;19:rgb_out=24'he5ca93;
   20:rgb_out=24'h417a89;21:rgb_out=24'h77a89a;22:rgb_out=24'hb4dce0;
   23:rgb_out=24'h283a72;24:rgb_out=24'h4e73b7;25:rgb_out=24'h84a9e2;
   26:rgb_out=24'hdf8d3e;27:rgb_out=24'hffbb61;28:rgb_out=24'hffe2a0;
   29:rgb_out=24'h5c6269;30:rgb_out=24'h9ea4a6;31:rgb_out=24'hdfdfd5;
   default:;
  endcase
  if(panel_q)rgb_out=24'h162737;
  if(text_q&&text_pixel)rgb_out=24'he7efec;
  if(zoom_dot_q)rgb_out=zoom_focus_q?24'h70d6bc:24'h3b5363;
  if(inside_q&&line_name_pixel[1])rgb_out=line_name_pixel[0]?24'he7efec:24'h0b1420;
 end
endmodule

// The nine orbital phases use the original synchronous 24-bit memory interface.
// Paired adjacent 16-bit addresses update both halves on the same clock edge.
// NOREG is the synchronous RAM read without an additional output register.
module solar_phase_ram(input wire clk,input wire [8:0] address,input wire write_enable,
 input wire [23:0] write_data,output wire [23:0] read_data);
`ifdef __ICARUS__
 // Behavioral contract; physical readback audits the actual primitive binding.
 reg [23:0] memory[0:511];reg [23:0] q;
 always @(posedge clk)begin
  q<=memory[address];
  if(write_enable)memory[address]<=write_data;
 end
 assign read_data=q;
`else
 wire [15:0] low_word,high_word;
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) storage(
  .doa(low_word),.dia(write_data[15:0]),.addra({1'd0,address,1'b0}),
  .bytea(1'b0),.bytewea(1'b0),.csa(1'b1),.wea(write_enable),.clka(clk),.rsta(1'b0),.ocea(1'b1),
  .dob(high_word),.dib({8'd0,write_data[23:16]}),.addrb({1'd0,address,1'b1}),
  .byteb(1'b0),.byteweb(1'b0),.csb(1'b1),.web(write_enable),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
 assign read_data={high_word[7:0],low_word};
`endif
endmodule

// Two 512x2 line banks replace ten parallel per-pixel name comparisons.
// Compose the next row while scanning this row. The sidebar owns its font
// port for at most 128 clocks of each 800-clock line; clearing 384 pixels,
// drawing all nine names (240 pixels), and control fit within that interval.
module scene_label_line_cache(
 input wire clk,rst_n,enable,scene_mode,de,
 input wire [9:0] x,y,
 input wire [69:0] anchors_x,anchors_y,
 input wire font_available,font_pixel,
 output wire font_request,output wire [14:0] font_address,
 output wire [1:0] name_pixel);
 localparam IDLE=0,CLEAR=1,SELECT=2,FETCH=3,FINISH=4;
 reg [2:0] state;
 reg de_prev,write_bank,pending_valid,read_ready;
 reg [1:0] bank_ready;
 reg [9:0] compose_y,pending_address;
 reg [8:0] clear_x,write_x;
 reg [3:0] name_index;
 reg [5:0] column,last_column;
 reg [7:0] font_row;
 wire line_start=de&&!de_prev;
 wire [6:0] anchor_x=anchors_x[name_index*7+:7];
 wire [6:0] anchor_y=anchors_y[name_index*7+:7];
 wire [8:0] name_top=9'd48+{1'b0,anchor_y,1'b0}+{2'd0,anchor_y};
 wire [9:0] relative_y=compose_y-{1'b0,name_top};
 wire active_name=scene_mode?(name_index==2||name_index==9):(name_index<9);
 function [7:0] glyph_row_base;
  input [3:0] n;
  begin case(n)
   0:glyph_row_base=24;1:glyph_row_base=44;2:glyph_row_base=64;
   3:glyph_row_base=84;4:glyph_row_base=104;5:glyph_row_base=124;
   6:glyph_row_base=144;7:glyph_row_base=164;8:glyph_row_base=0;
   9:glyph_row_base=192;default:glyph_row_base=0;
  endcase end
 endfunction
 assign font_request=enable&&state==FETCH&&font_available&&!line_start;
 assign font_address={font_row,(7'd4+{1'b0,column})};
 (* ram_style="bram" *) reg [1:0] memory[0:1023];
 reg [1:0] read_data;
 wire write_enable=enable&&!line_start&&(state==CLEAR||pending_valid);
 wire [9:0] write_address=(state==CLEAR)?{write_bank,clear_x}:pending_address;
 wire [1:0] write_data=(state==CLEAR)?2'd0:{1'b1,font_pixel};
 wire [8:0] read_x=x-10'd16;
 always @(posedge clk)begin
  if(write_enable)memory[write_address]<=write_data;
  read_data<=memory[{y[0],read_x}];
 end
 assign name_pixel=read_ready?read_data:2'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)read_ready<=0;
  else read_ready<=enable&&bank_ready[y[0]];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;de_prev<=0;write_bank<=0;pending_valid<=0;bank_ready<=0;
   compose_y<=0;pending_address<=0;clear_x<=0;write_x<=0;
   name_index<=0;column<=0;last_column<=0;font_row<=0;
  end else begin
   de_prev<=de;pending_valid<=font_request;
   if(font_request)pending_address<={write_bank,write_x};
   if(!enable)begin state<=IDLE;bank_ready<=0;pending_valid<=0;end
   else if(line_start)begin
    // A missed deadline leaves the incomplete bank invalid, never displayed.
    write_bank<=!y[0];bank_ready[!y[0]]<=0;compose_y<=y+1'b1;
    clear_x<=0;name_index<=0;pending_valid<=0;state<=CLEAR;
   end else case(state)
    CLEAR:if(clear_x==383)begin name_index<=0;state<=SELECT;end else clear_x<=clear_x+1'b1;
    SELECT:begin
     if(active_name&&relative_y<12)begin
      write_x<={1'b0,anchor_x,1'b0}+{2'd0,anchor_x};column<=0;
      last_column<=(name_index==6||name_index==7)?6'd35:6'd23;
      font_row<=glyph_row_base(name_index)+relative_y[7:0];state<=FETCH;
     end else if(name_index==9)state<=FINISH;
     else name_index<=name_index+1'b1;
    end
    FETCH:if(font_request)begin
     write_x<=write_x+1'b1;column<=column+1'b1;
     if(column==last_column)begin
      if(name_index==9)state<=FINISH;
      else begin name_index<=name_index+1'b1;state<=SELECT;end
     end
    end
    FINISH:begin bank_ready[write_bank]<=1;state<=IDLE;end
    default:;
   endcase
  end
 end
endmodule
