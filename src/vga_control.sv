module vga_control(

input o_vga_clock,
input reset_n,
input test_mode,          // put device in VGA Test mode

input P1_L,P1_R,
input P2_L,P2_R,

output o_hsync,
output o_vsync,
output o_sync,
output o_blank,
output [7:0] o_red,
output [7:0] o_green,
output [7:0] o_blue

);
// ________________________________________________________________________________
// ROM 
// ________________________________________________________________________________
    
    // rom regs
    logic [18:0] rom_address;      // Address to access ROM
    logic [8:0] rom_output;        // Output from ROM containing pixel data

    // connecting the ROM
    beach image(
    .address(rom_address),
    .clock(o_vga_clock),
    .q(rom_output)
    );
	 
	 // ball sprite rom
	 logic [10:0] ball_sprite_address;
	 logic [3:0] ball_sprite_output;
	 
	 // connecting ball sprite
	 ball ball(
	.address(ball_sprite_address),
	.clock(o_vga_clock),
	.q(ball_sprite_output));

    // wizard character rom
    logic [13:0] sprite_address_1;	 
    logic [13:0] sprite_address_2;
    logic [6:0] sprite_output_1;
    logic [6:0] sprite_output_2;
	
	Sprites wizard(
	.address_a(sprite_address_1),
	.address_b(sprite_address_2),
	.clock(o_vga_clock),
	.q_a(sprite_output_1),
	.q_b(sprite_output_2));
	
	
	// game over page
    logic [18:0] over_address;      // Address to access ROM
    logic over_screen_output;        // Output from ROM containing pixel data
	game_over final_screen(
	.address(over_address),
	.clock(o_vga_clock),
	.q(over_screen_output));

// ################################################################################

// ________________________________________________________________________________
// VGA Screen 
// ________________________________________________________________________________
   
    // VGA 640x480 Timing Parameters
    parameter H_ACTIVE  = 10'd640;
    parameter H_FRONT   = 10'd16;
    parameter H_PULSE   = 10'd96;
    parameter H_BACK    = 10'd48;
    
    parameter V_ACTIVE  = 10'd480;
    parameter V_FRONT   = 10'd10;
    parameter V_PULSE   = 10'd2;
    parameter V_BACK    = 10'd33;

    // counters for hsync and vsync signals
    logic signed [10:0] h_counter = 0;
    logic signed [10:0] v_counter = 0;
    
    logic hsync_reg = 1;
    logic vsync_reg = 1;
    
    // 8 bit color regs for R, G and B
    logic [7:0] red_reg = 0;
    logic [7:0] green_reg = 0;
    logic [7:0] blue_reg = 0;

// ################################################################################

// ________________________________________________________________________________
// Sprite Movements 
// ________________________________________________________________________________

    // movement constants
    parameter gravity = 1;
	 parameter collision_boost = 2;
	 // 
	 parameter max = 10;

    // sprite select lines
    logic ball_on;
    logic P1_on;
    logic P2_on;
    logic net_on;
	 
	 // net parameter
	 parameter net_height = 200;

    // Sprite Sizing parameers
    parameter R_ball = 20;
    parameter R_P1 = 60;
    parameter R_P2 = 60;

    // screen dimensions
    parameter top = 0;
    parameter bottom = 480;
    parameter left = 0;
    parameter right = 640;
    parameter middle = 320;

    // ball boundaries
    parameter Ball_left_bound = left + R_ball;
    parameter Ball_right_bound = right - R_ball;

    // position and velocity variables
    logic signed [max:0] pBx,pBy;   // Position of Ball (pBx, pBy)
    logic signed [max:0] pP1x,pP1y; // Position of Player 1 (pP1x, pP1y)
    logic signed [max:0] pP2x,pP2y; // Position of Player 2 (pP2x, pP2y)

    logic signed [max:0] vBx,vBy;   // Velocity of Ball (pBx, pBy)
    logic signed [max:0] vP1x,vP1y; // Velocity of Player 1 (pP1x, pP1y)
    logic signed [max:0] vP2x,vP2y; // Velocity of Player 2 (pP2x, pP2y)
    

    // flags for screen refresh
    logic refresh;
    logic [5:0] refresh_counter;

	 
     initial begin
     $monitor("Ball: %0d, %0d;  P1: %0d, %0d; P2: %0d, %0d;",pBx, pBy, pP1x, pP1y, pP2x, pP2y);
     end
// ################################################################################

// ________________________________________________________________________________
// Score System 
// ________________________________________________________________________________
parameter MAX_SCORE = 100;
parameter reduction_jumps = 20;

logic game_over;

parameter LEFT_BAR_X1 = 21;
//parameter LEFT_BAR_X2 = 219;

parameter RIGHT_BAR_X1 = 421;
//parameter RIGHT_BAR_X2 = 619;

parameter LEFT_BAR_Y1 = 12;
parameter LEFT_BAR_Y2 = 18;

parameter RIGHT_BAR_Y1 = 12;
parameter RIGHT_BAR_Y2 = 18;

logic [9:0] p1_score,p2_score;
logic [9:0] p1_bar_end, p2_bar_end;

always_comb begin
    // Linearly map score to pixels: bar goes from X1 to X1 + max_width
    p1_bar_end = LEFT_BAR_X1 + ((198 * p1_score) / MAX_SCORE);  // 219 - 21 = 198
    p2_bar_end = RIGHT_BAR_X1 + ((198 * p2_score) / MAX_SCORE); // 619 - 421 = 198
end
// ################################################################################
logic ball_in_left_half;

logic [5:0] ball_sprite_x;
logic [5:0] ball_sprite_y;

logic [6:0] p1_sprite_X;
logic [6:0] p1_sprite_y;

logic [6:0] p2_sprite_X;
logic [6:0] p2_sprite_y;

always @(posedge o_vga_clock or negedge reset_n)begin
    if(!reset_n)begin
        // vga screen resets    
            h_counter <= 0;
            v_counter <= 0;
            hsync_reg <= 1;
            vsync_reg <= 1;     
				
        // sprite resets
           ball_sprite_x <= 0;
           ball_sprite_y <= 0;
           ball_sprite_address <= 0;

			  p1_sprite_X <= 0;
			  p1_sprite_y <= 0;
			  sprite_address_1 <= 0;
			  
			  p2_sprite_X <= 0;
			  p2_sprite_y <= 0;			  
			  sprite_address_2 <= 0;
			  			  
    end else begin

//  ________________________________________________________________________________
//    VGA Screen Logic 
//  ________________________________________________________________________________
     
    // H and V counters
    if (h_counter < H_ACTIVE + H_FRONT + H_PULSE + H_BACK)
        h_counter <= h_counter + 1;
    else begin
        h_counter <= 0;
        if (v_counter < V_ACTIVE + V_FRONT + V_PULSE + V_BACK)
            v_counter <= v_counter + 1;
        else
            v_counter <= 0;
    end
        
    // HSYNC Control
    if (h_counter >= H_ACTIVE + H_FRONT && h_counter < H_ACTIVE + H_FRONT + H_PULSE)
        hsync_reg <= 0;
    else
        hsync_reg <= 1;

    // VSYNC Control
    if (v_counter >= V_ACTIVE + V_FRONT && v_counter < V_ACTIVE + V_FRONT + V_PULSE)
        vsync_reg <= 0;
    else
        vsync_reg <= 1;
  		  
// ################################################################################

//  ________________________________________________________________________________
//    Test Screen Logic 
//  ________________________________________________________________________________
  
    if(test_mode)begin
		 if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
				 rom_address = (v_counter * H_ACTIVE + h_counter); // Calculate the address based on pixel row and column
				 // Extract RGB from 8-bit value (RGB332 format)
				 red_reg   <= {rom_output[8:6],rom_output[8:6],rom_output[8:7]};   
				 green_reg <= {rom_output[5:3],rom_output[5:3],rom_output[5:4]};
				 blue_reg  <= {rom_output[2:0],rom_output[2:0],rom_output[2:1]};  
		 end
	 end
// ################################################################################
//  ________________________________________________________________________________
//    Actual Display based on Sprite Select signals 
//  ________________________________________________________________________________
  
    else begin

        if(ball_on)begin
            if(ball_sprite_x <41 && ball_sprite_y < 41)begin
				ball_sprite_x <= h_counter - (pBx - R_ball);
                ball_sprite_y <= v_counter - (pBy - R_ball);
                ball_sprite_address <= ball_sprite_y * 40 + ball_sprite_x;
					 
				if(ball_sprite_output[3])begin
                    red_reg <= {8{ball_sprite_output[2]}};
                    green_reg <= {8{ball_sprite_output[1]}};
                    blue_reg <= {8{ball_sprite_output[0]}};
                end

                else begin
                    if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
                    rom_address = (v_counter * H_ACTIVE + h_counter);
                    red_reg   <= {rom_output[8:6],rom_output[8:6],rom_output[8:7]};   
				        green_reg <= {rom_output[5:3],rom_output[5:3],rom_output[5:4]};
				        blue_reg  <= {rom_output[2:0],rom_output[2:0],rom_output[2:1]};
                    end 
                end
            end
            else begin
                ball_sprite_x <= 0;
                ball_sprite_y <= 0;
            end
		end    
        else if(P1_on)begin
            //
            if(p1_sprite_X <121 && p1_sprite_y < 121)begin
				    p1_sprite_X <= h_counter - (pP1x - R_P1);
                p1_sprite_y <= v_counter - (pP1y - R_P1);
                sprite_address_1 <= p1_sprite_y * 120 + p1_sprite_X;
					 
				if(sprite_output_1[6])begin
                    red_reg <= {4{sprite_output_1[5:4]}};
                    green_reg <= {4{sprite_output_1[3:2]}};
                    blue_reg <= {4{sprite_output_1[1:0]}};
                end
                else begin
                    if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
                    rom_address = (v_counter * H_ACTIVE + h_counter);
                    red_reg   <= {rom_output[8:6],rom_output[8:6],rom_output[8:7]};   
				        green_reg <= {rom_output[5:3],rom_output[5:3],rom_output[5:4]};
				        blue_reg  <= {rom_output[2:0],rom_output[2:0],rom_output[2:1]};
                    end 
                end
            end
            else begin
                p1_sprite_X <= 0;
                p1_sprite_y <= 0;
            end
        end
        
        else if(P2_on)begin
            //
            if(p2_sprite_X <121 && p2_sprite_y < 121)begin
				    p2_sprite_X <= h_counter - (pP2x - R_P2);
                p2_sprite_y <= v_counter - (pP2y - R_P2);
                sprite_address_2 <= p2_sprite_y * 120 + p2_sprite_X;
					 
				if(sprite_output_2[6])begin
                    red_reg <= {4{sprite_output_2[5:4]}};
                    blue_reg <= {4{sprite_output_2[3:2]}};
                    green_reg <= {4{sprite_output_2[1:0]}};
                end
                else begin
                    if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
                    rom_address = (v_counter * H_ACTIVE + h_counter);
                    red_reg   <= {rom_output[8:6],rom_output[8:6],rom_output[8:7]};   
				        green_reg <= {rom_output[5:3],rom_output[5:3],rom_output[5:4]};
				        blue_reg  <= {rom_output[2:0],rom_output[2:0],rom_output[2:1]};
                    end 
                end
            end
            else begin
                p2_sprite_X <= 0;
                p2_sprite_y <= 0;
            end
        end

        else if(score_bar_boundary)begin
            red_reg <= 8'h00;
            green_reg <= 8'h00;
            blue_reg <= 8'h00;
        end
		  
        else if(red_fill_1 || red_fill_2)begin
        red_reg <= 8'hff;
        green_reg <= 8'h00;
        blue_reg <= 8'h00;
        end
		  else if(net_on)begin
        red_reg <= 8'h00;
        green_reg <= 8'h00;
        blue_reg <= 8'h00;
        end  
        else begin
			 if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
				 rom_address = (v_counter * H_ACTIVE + h_counter);
			     red_reg   <= {rom_output[8:6],rom_output[8:6],rom_output[8:7]};   
				 green_reg <= {rom_output[5:3],rom_output[5:3],rom_output[5:4]};
				 blue_reg  <= {rom_output[2:0],rom_output[2:0],rom_output[2:1]};
		    end   
		end
		
		 if(game_over)begin
		 if (h_counter < H_ACTIVE && v_counter < V_ACTIVE) begin
				 over_address = (v_counter * H_ACTIVE + h_counter); // Calculate the address based on pixel row and column
				 // Extract RGB from 8-bit value (RGB332 format)
				 
				 if(over_screen_output)begin //red
					 red_reg <= 8'hff;
					 green_reg <= 8'h00;
					 blue_reg <= 8'h00;
				 end 
				 else begin //black
				 red_reg   <= 8'h00;
				 green_reg <= 8'h00;
				 blue_reg  <= 8'h00;
			    end	 
		  end
		  end
	 end
    end
end

//  ________________________________________________________________________________
//    Updating positions of Sprites
//  ________________________________________________________________________________ 
always @(posedge o_vga_clock or negedge reset_n) begin
    if (!reset_n) begin
        refresh <= 0;
        refresh_counter <= 0;
    end else begin
        refresh <= 0; 

        if ((v_counter== 0) && (h_counter == 0)) begin
            if (refresh_counter == 7) begin
                refresh_counter <= 0;
                refresh <= 1; 
            end else begin
                refresh_counter <= refresh_counter + 1;
					 refresh <= 0;
            end
        end
    end
end

// start ball on left side.
always @(posedge o_vga_clock or negedge reset_n)begin
if(!reset_n)begin
// Positions
            // position of ball
            pBx <= 159;
            pBy <= 150;
            

            // position of P1
            pP1x <= 159;
            pP1y <= bottom - R_P1;

            // postions of  P2
            pP2x <= 479;
            pP2y <= bottom - R_P2;

            // Velocities
            // ball velocity
              vBx <= 0;
              vBy <= 0;
				  
				// more like a health bar
				p1_score <= 100;
				p2_score <= 100;	
				game_over <= 0;
		
end
else begin
    // entire sprite movement logic
    if(refresh)begin
    		ball_in_left_half <= 1;
			pBx <= pBx + vBx;
			
			// put a gradual cap on horizontal velocity
			if(vBx > 16)begin
			vBx <= vBx - 1;
			end
			if(vBx < -16)begin
			vBx <= vBx + 1;
			end
			
			// put a gradual cap on vertical velocity
			if(vBy > 16)begin
			vBy <= vBy - 2;
			end
			if(vBy < -16)begin
			vBy <= vBy + 2;
			end

         // Wall Bounce
	        // left wall
			if (pBx - R_ball <= 0) begin
				pBx <= R_ball + 1;
				vBx <= -(vBx + collision_boost);
			end
			// right wall
			if (pBx + R_ball  >= 640) begin
				 pBx <= right - R_ball - 1;
				 vBx <= -(vBx + collision_boost);
			end	

		// which side of court ball is on
            if(pBx < middle)begin
                ball_in_left_half <= 1;
            end
            else begin
                ball_in_left_half <= 0;
            end

        // Net collisions
            if(pBx > middle - R_ball && pBx < middle + R_ball && pBy >= bottom - net_height )begin
               
                if(ball_in_left_half)begin
                    pBx <= middle - R_ball - 2;
                end
                else begin 
                    pBx <= middle + R_ball + 2;
                end
                vBx <= -vBx;
            end


		// check ball collision with character
			if((pBy + R_ball >= 360) && ((pBx <= pP1x + R_P1) && (pBx >= pP1x - R_P1)))begin
			  pBy <= pP1y - R_P1 - R_ball-2;
			  vBy <= -(vBy - 2);
           vBx <= ((vP1x * 7) + (vBx * 1)) >> 3; // momentum transfer logic for decimal numbers
			end
			// check for other character
			else if((pBy +R_ball >= 360) && ((pBx <= pP2x + R_P2) && (pBx >= pP2x - R_P2)))begin
			  pBy <= pP2y - R_P2 - R_ball-2;
			  vBy <= -(vBy - 2);
           vBx <= ((vP2x * 7) + (vBx * 1)) >> 3;
			end

			// check for ground collision
		   else if(pBy + R_ball >= bottom)begin
            pBy <= bottom - R_ball -2;
            vBy <= - (vBy - 3);




			// check whose score to reduce
                // left player concedes point
				if(pBx < middle)begin
                    p1_score <= p1_score - reduction_jumps;
						  if(p1_score == 20) game_over <= 1;
                    // reset and give serve to right player
                    pBx <= 480;
                    pBy <= 150;
						  vBx <= 0;
						  vBy <= 0;
                end
                // right player concedes point
                else begin
                    p2_score <= p2_score - reduction_jumps;
						  if(p2_score == 20) game_over <= 1;
                    // reset and give serve to left player
                    pBx <= 160;
                    pBy <= 150;
						  vBx <= 0;
						  vBy <= 0;
                end
		   end
			// normal free fall
         else begin
            pBy <= pBy + vBy;
            vBy <= vBy + gravity;
         end
			
			
        // player movements
        if(!P1_L)begin
            if(pP1x >= R_P1)begin
		      vP1x <= vP1x - 3;
            pP1x <= pP1x + vP1x;
            end
        end
        else if(!P1_R)begin
		  if(pP1x <= middle - R_P1)begin
            vP1x <= vP1x + 3;
            pP1x <= pP1x + vP1x; 
		  end
		  end
        else begin
            pP1x <= pP1x;
				vP1x <= 0;
        end
        if(!P2_L)begin
            if(pP2x >= middle + R_P2)begin
		      vP2x <= vP2x - 3;
            pP2x <= pP2x + vP2x;
            end
        end
        else if(!P2_R)begin
            if(pP2x <= right - R_P2)begin
            vP2x <= vP2x + 3;
            pP2x <= pP2x + vP2x; 
		  end
        end
        else begin
            pP2x <= pP2x;
			   vP2x <= 0;
        end
    end
end

end
//  ________________________________________________________________________________
//    Assignments for VGA Screen
//  ________________________________________________________________________________
  
assign o_hsync = hsync_reg;
assign o_vsync = vsync_reg;
assign o_red = red_reg;
assign o_green = green_reg;
assign o_blue = blue_reg;
assign o_sync = 1'b0;
assign o_blank = hsync_reg & vsync_reg;

//  ________________________________________________________________________________
//    Multiplexing signals for sprites
//  ________________________________________________________________________________

assign ball_on = ((pBx <= h_counter + R_ball) && (pBx >= h_counter - R_ball) && (pBy <= v_counter + R_ball) && (pBy >= v_counter - R_ball));
assign net_on = ((h_counter >= middle - 2) && (h_counter <= middle + 2) && (v_counter >= bottom - net_height) && (pBy <= bottom));
assign P1_on =  ((pP1x <= h_counter + R_P1) && (pP1x >= h_counter - R_P1) && (pP1y <= v_counter + R_P1) && (pP1y >= v_counter - R_P1));
assign P2_on =  ((pP2x <= h_counter + R_P2) && (pP2x >= h_counter - R_P2) && (pP2y <= v_counter + R_P2) && (pP2y >= v_counter - R_P2));
assign score_bar_boundary = (!red_fill_1 && !red_fill_2)? ((h_counter > 20 && h_counter < 220) && (v_counter >= 10 && v_counter <= 20) || (h_counter > 420 && h_counter < 620) && (v_counter >= 10 && v_counter <= 20)) : 0;
assign red_fill_1 = (h_counter > LEFT_BAR_X1 && h_counter < p1_bar_end) && (v_counter >= LEFT_BAR_Y1 && v_counter <= LEFT_BAR_Y2) ;
assign red_fill_2 = (h_counter > RIGHT_BAR_X1 && h_counter < p2_bar_end) && (v_counter >= RIGHT_BAR_Y1 && v_counter <= RIGHT_BAR_Y2);
endmodule
