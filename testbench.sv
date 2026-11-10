`timescale 1ns/1ps

interface io;
    logic PCLK;
    logic PRESETn;
    logic PSEL;
    logic PENABLE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic PWRITE;
    logic [31:0] PRDATA;
    logic PREADY;
    logic PSLVERR;
endinterface

class transaction;
    logic PRESETn;
    logic PSEL;
    logic PENABLE;
    rand bit [31:0] PADDR;
    rand bit [31:0] PWDATA;
    rand bit PWRITE;
    logic [31:0] PRDATA;
    logic PREADY;
    logic PSLVERR;

    constraint addr_c {
        PADDR inside {[0:124]};
        PADDR[1:0] == 2'b00;
    }
endclass

class generator;
    mailbox #(transaction) gen2drv;
    int count;

    function new(mailbox #(transaction) gen2drv, int count);
        this.gen2drv = gen2drv;
        this.count = count;
    endfunction

    task main();
        transaction tr;
        repeat (count) begin
            tr = new();
            if (!tr.randomize())
                $display("ERROR in RANDOMIZATION");
            $display("[GEN] | PADDR= %0d, PWDATA= %0d, PWRITE= %b", tr.PADDR, tr.PWDATA, tr.PWRITE);
            gen2drv.put(tr);
        end
    endtask
endclass

class driver;
    mailbox #(transaction) gen2drv;
    virtual io vif;
    int count;
    event drv_done;

    function new(mailbox #(transaction) gen2drv, virtual io vif, int count);
        this.gen2drv = gen2drv;
        this.vif = vif;
        this.count = count;
    endfunction

    task main();
        transaction tr;

        // Reset 
        vif.PRESETn = 1'b1;
        vif.PSEL    = 0;
        vif.PENABLE = 0;
        vif.PADDR   = 32'b0;
        vif.PWDATA  = 32'b0;
        vif.PWRITE  = 0;
        $display("[DRV] Reset Asserted");

        @(negedge vif.PCLK);
        vif.PRESETn = 1'b0;
        $display("[DRV] Reset Deasserted");

        repeat (count) begin
            gen2drv.get(tr);

            // setup phase
            @(negedge vif.PCLK);
            vif.PSEL    = 1'b1;
            vif.PENABLE = 1'b0;
            vif.PADDR   = tr.PADDR;
            vif.PWDATA  = tr.PWDATA;
            vif.PWRITE  = tr.PWRITE;

            // access phase
            @(negedge vif.PCLK);
            vif.PENABLE = 1'b1;

            // end 
            @(negedge vif.PCLK);
            vif.PSEL    = 1'b0;
            vif.PENABLE = 1'b0;
        end

        $display("[DRV] ALL %0d TRANSACTIONS COMPLETED", count);
        -> drv_done;
    endtask
endclass

class monitor;
    mailbox #(transaction) mon2scb;
    virtual io vif;
    int count;

    function new(mailbox #(transaction) mon2scb, virtual io vif, int count);
        this.mon2scb = mon2scb;
        this.vif = vif;
        this.count = count;
    endfunction

    task main();
        transaction tr;
        int seen = 0;

        while (seen < count) begin
            @(posedge vif.PCLK);

            if (vif.PRESETn == 0 && vif.PSEL && vif.PENABLE && vif.PREADY) begin
                tr = new();
                tr.PRESETn = vif.PRESETn;
                tr.PSEL    = vif.PSEL;
                tr.PENABLE = vif.PENABLE;
                tr.PADDR   = vif.PADDR;
                tr.PWDATA  = vif.PWDATA;
                tr.PWRITE  = vif.PWRITE;
                tr.PRDATA  = vif.PRDATA;
                tr.PREADY  = vif.PREADY;
                tr.PSLVERR = vif.PSLVERR;

                $display("[MON] | PRESET= %b, PSEL= %b, PENABLE= %b, PADDR= %0d, PWDATA= %0d, PWRITE= %b, PRDATA= %0d, PREADY= %b, PSLVERR= %b",
                         tr.PRESETn, tr.PSEL, tr.PENABLE, tr.PADDR, tr.PWDATA, tr.PWRITE, tr.PRDATA, tr.PREADY, tr.PSLVERR);

                mon2scb.put(tr);
                seen++;
            end
        end
    endtask
endclass

class scoreboard;
    mailbox #(transaction) mon2scb;
    int count;
    bit [31:0] temp;
    logic [31:0] ref_mem [31:0];
    int pass_count = 0;
    int err_count  = 0;
    int wr_count   = 0;

    function new(mailbox #(transaction) mon2scb, int count);
        this.mon2scb = mon2scb;
        this.count = count;
    endfunction

    task main();
        transaction tr;

        foreach (ref_mem[i]) ref_mem[i] = 32'b0;

        repeat (count) begin
            mon2scb.get(tr);

            if (tr.PWRITE) begin
                ref_mem[tr.PADDR[6:2]] = tr.PWDATA;
                wr_count++;
                $display("[SCB] WRITE addr=%0d data=%0d", tr.PADDR, tr.PWDATA);
            end
            
            else begin
                temp = ref_mem[tr.PADDR[6:2]];
                if (tr.PRDATA === temp) begin
                    $display("[SCB] Data Match    addr=%0d exp=%0d got=%0d", tr.PADDR, temp, tr.PRDATA);
                    pass_count++;
                end
                else begin
                    $display("[SCB] Data MisMatch addr=%0d exp=%0d got=%0d", tr.PADDR, temp, tr.PRDATA);
                    err_count++;
                end
            end
        end

        $display("--------------------------------");
        $display("[SCB] WRITES     = %0d", wr_count);
        $display("[SCB] PASS COUNT = %0d", pass_count);
        $display("[SCB] ERROR COUNT= %0d", err_count);
        $display("--------------------------------");
    endtask
endclass

class environment;
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv;
    mailbox #(transaction) mon2scb;
    virtual io vif;
    int count;

    function new(virtual io vif, int count);
        gen2drv = new();
        mon2scb = new();
        this.vif = vif;
        this.count = count;

        gen = new(gen2drv, count);
        drv = new(gen2drv, vif, count);
        mon = new(mon2scb, vif, count);
        scb = new(mon2scb, count);
    endfunction

    task test();
        fork
            gen.main();
            drv.main();
            mon.main();
            scb.main();
        join
    endtask
endclass

module APB_tb;
    io my_io();

    APB dut(
        .PCLK    (my_io.PCLK),
        .PRESETn (my_io.PRESETn),
        .PSEL    (my_io.PSEL),
        .PENABLE (my_io.PENABLE),
        .PADDR   (my_io.PADDR),
        .PWDATA  (my_io.PWDATA),
        .PWRITE  (my_io.PWRITE),
        .PRDATA  (my_io.PRDATA),
        .PREADY  (my_io.PREADY),
        .PSLVERR (my_io.PSLVERR)
    );

    initial begin
        my_io.PCLK = 0;
        forever #5 my_io.PCLK = ~my_io.PCLK;
    end

    environment env;

    initial begin
        
        $dumpfile("APB.vcd");
        $dumpvars(0, APB_tb);

        env = new(my_io, 100);
        env.test();

        #20;
        $finish;
    end

endmodule
