module APB(
    input logic PCLK,
    input logic PRESETn,
    input logic PSEL,
    input logic PENABLE,
    input logic [31:0] PADDR,
    input logic [31:0] PWDATA,
    input logic PWRITE,
    output logic [31:0] PRDATA,
    output logic PREADY,
    output logic PSLVERR
);

    logic [31:0] register [31:0];   // peripheral registers

    typedef enum logic [1:0]{
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } state;

    state curr_state;
    state next_state;

    assign PREADY  = 1'b1; // Always ready (zero-wait-state)
    assign PSLVERR = 1'b0; // No error generation

    always_ff @(posedge PCLK) begin
        if (PRESETn) begin
            curr_state <= IDLE;
        end
        
        else begin
            curr_state <= next_state;

        end
    end

    always_comb begin
        case(curr_state) 

        IDLE : begin
                
                if(PSEL == 1 && PENABLE == 0) 
                    next_state = SETUP;

                else
                    next_state = IDLE;
        end

        SETUP : begin

                    if(PSEL == 1 && PENABLE == 1)
                        next_state = ACCESS;

                    else 
                        next_state = SETUP;
        end

        ACCESS: begin
            if(PREADY) begin
                if(PSEL && !PENABLE)
                    next_state = SETUP;
                else
                    next_state = IDLE;
            end
            else
                next_state = ACCESS;
        end
        
        default : next_state = IDLE;
        endcase
    end

        // write
    always_ff @(posedge PCLK) begin
        if (PRESETn) begin
            for (int i = 0; i < 32; i++) register[i] <= '0;
        end
        else if (PSEL && PENABLE && PWRITE && PREADY)
            register[PADDR[6:2]] <= PWDATA;
    end

    // read
    always_comb begin
        PRDATA = '0;
        if (PSEL && PENABLE && !PWRITE && PREADY)
            PRDATA = register[PADDR[6:2]];
    end

endmodule
