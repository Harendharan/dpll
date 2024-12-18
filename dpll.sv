
`timescale 1ns / 1ps

class transaction;
   rand int fin_frequency;      // PLL clock input (clk_fin) frequency
   int fout_frequency;          // PLL clock output (clk_fout) frequency
   int fout_phase;              // PLL clock output (clk_fout) phase
   int fout8x_frequency;        // PLL 8x clock output (clk8x_fout) frequency

   constraint fin_frequency_con {
      // Center of the lock range is 100 MHz / 2^32 = 390.625 kHz
      fin_frequency >= 390625 - 200;
      fin_frequency <= 390625 + 200;
   }

   function void display(input string tag);
      $display("[%0s] fin: %7d Hz     fout: %7d Hz %3d degrees  (from fin)     fout8x: %7d Hz",
               tag, fin_frequency, fout_frequency, fout_phase, fout8x_frequency);
   endfunction

   function transaction copy();
      copy = new();
      copy.fin_frequency      = this.fin_frequency;
      copy.fout_frequency     = this.fout_frequency;
      copy.fout_phase         = this.fout_phase;
      copy.fout8x_frequency   = this.fout8x_frequency;
   endfunction
endclass

class generator;
   transaction trn;
   mailbox #(transaction) g2d_mbx;     // Mailbox for data from generator to driver (g2d)
   event done;                         // Generator has completed the requested number of transactions
   event next;                         // Scoreboard has completed the previous transaction
   int count = 0;                      // Number of transactions to do per run()

   function new (mailbox #(transaction) g2d_mbx);
      this.g2d_mbx = g2d_mbx;
      trn = new();
   endfunction

   task run();
      repeat(count) begin
         assert(trn.randomize) else $error("Randomization Failed");

         $display("-----------------------------------------------------------------------------------------------------");
         trn.display("GEN");
         g2d_mbx.put(trn);
         @(next);
      end

      ->done;
   endtask
endclass

class driver;
   virtual dpll_if dif;
   transaction trn;
   mailbox #(transaction) g2d_mbx;
   mailbox #(transaction) d2m_mbx;
   event next;          // Only used for testing in drv_tb
   int fin_period;

   function new(mailbox #(transaction) g2d_mbx, mailbox #(transaction) d2m_mbx);
      this.g2d_mbx = g2d_mbx;
      this.d2m_mbx = d2m_mbx;
   endfunction

   task reset();
      dif.reset <= 1'b1;
      dif.clk_fin <= 1'b0;

      repeat(5) @(posedge dif.clk);
      dif.reset <= 1'b0;
      $display("[DRV] RESET DONE");
   endtask

   task run();
      forever begin
         g2d_mbx.get(trn);
         d2m_mbx.put(trn);       // Send a reference copy of the transaction to the scoreboard
         trn.display("DRV");

         fin_period = int'((1/(real'(trn.fin_frequency))) * 1000000000);
         $display("[DRV] fin_period: %0d", fin_period);

         dif.clk_fin = 1'b0;
         @(posedge dif.clk);

         // Wait for about 1ms for the PLL to settle
         repeat(500) begin
            #(fin_period/2)
            dif.clk_fin = 1'b1;
            #(fin_period/2)
            dif.clk_fin = 1'b0;
         end

         ->next;
      end
   endtask
endclass

class monitor;
   virtual dpll_if dif;
   transaction d2m_trn;
   transaction m2s_trn;
   mailbox #(transaction) d2m_mbx;
   mailbox #(transaction) m2s_mbx;

   function new(mailbox #(transaction) d2m_mbx, mailbox #(transaction) m2s_mbx);
      this.d2m_mbx = d2m_mbx;
      this.m2s_mbx = m2s_mbx;
   endfunction

   // Calculate the frequency of clk_fout using the after of 10 periods
   task check_fout_frequency();
      time fout_posedge;
      time fout_last_posedge;
      int fout_period;
      real sum_fout_periods;
      real average_fout_period;

      @(posedge dif.clk_fout)
      fout_posedge = $time;

      sum_fout_periods = 0;
      repeat(10) begin
         @(posedge dif.clk_fout);
         fout_last_posedge = fout_posedge;
         fout_posedge = $time;
         fout_period = fout_posedge - fout_last_posedge;
         sum_fout_periods = sum_fout_periods + real'(fout_period);
      end

      average_fout_period = sum_fout_periods / 10;
      m2s_trn.fout_frequency = int'(1/(real'(average_fout_period)/1000000000));
   endtask

   // Calculate the phase of clk_fout relative to clk_fin
   task check_fout_phase();
      time fin_posedge;
      time fout_before_fin;
      time fout_after_fin;
      int fout_phase1;
      int fout_phase2;

      @(posedge dif.clk_fout);
      fout_before_fin = $time;

      @(posedge dif.clk_fin);
      fin_posedge = $time;

      @(posedge dif.clk_fout);
      fout_after_fin = $time;

      fout_phase1 = fin_posedge - fout_before_fin;
      fout_phase2 = fout_after_fin - fin_posedge;

      if (fout_phase1 <= fout_phase2) begin
         m2s_trn.fout_phase = -(fout_phase1 * 360) / 2560;
      end
      else begin
         m2s_trn.fout_phase = (fout_phase2 * 360) / 2560;
      end
   endtask

   // Calculate the frequency of clk8x_fout using the after of 10 periods
   task check_fout8x_frequency();
      time fout8x_posedge;
      time fout8x_last_posedge;
      int fout8x_period;
      real sum_fout8x_periods;
      real average_fout8x_period;

      @(posedge dif.clk8x_fout)
      fout8x_posedge = $time;

      sum_fout8x_periods = 0;
      repeat(10) begin
         @(posedge dif.clk8x_fout);
         fout8x_last_posedge = fout8x_posedge;
         fout8x_posedge = $time;
         fout8x_period = fout8x_posedge - fout8x_last_posedge;
         sum_fout8x_periods = sum_fout8x_periods + real'(fout8x_period);
      end

      average_fout8x_period = sum_fout8x_periods / 10;
      m2s_trn.fout8x_frequency = int'(1/(real'(average_fout8x_period)/1000000000));
   endtask

   task run();
      forever begin
         d2m_mbx.get(d2m_trn);         // Grab the transaction data from the driver and copy it
         m2s_trn = d2m_trn.copy();     // to the transaction destined for the the scoreboard.

         repeat(489) @(posedge dif.clk_fout); // Ignore the first 490 cycles of clk_fout;
         
         fork
            check_fout_frequency();
            check_fout_phase();
            check_fout8x_frequency();
         join

         m2s_mbx.put(m2s_trn);
         m2s_trn.display("MON");
      end
   endtask
endclass

class scoreboard;
   mailbox #(transaction) m2s_mbx;
   transaction trn;
   transaction ref_trn;
   event next;
   int fd;

   function new(mailbox #(transaction) m2s_mbx);
      this.m2s_mbx = m2s_mbx;
   endfunction

   task write_log_header();
      $fdisplay(fd, "fin_frequency,fout_frequency,fout_phase,fout8x_frequency,matched");

   endtask

   task write_log_data(int matched);
      $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d",
               trn.fin_frequency, trn.fout_frequency, trn.fout_phase, trn.fout8x_frequency, matched);
   endtask

   task run();
      forever begin
         m2s_mbx.get(trn);
         trn.display("SCO");

         // Check output frequency and phase
         if ((trn.fout_frequency == 390625) && ((trn.fout_phase < 1) || (trn.fout_phase > -1))
          && (trn.fout8x_frequency = 3125000)) begin
            $display("[SCO] DATA MATCHED");
            write_log_data(1);
         end
         else begin
            $display("[SCO] DATA MISMATCHED");
            write_log_data(0);
         end

         ->next;
      end
   endtask
endclass

class environment;
   generator   gen;
   driver      drv;
   monitor     mon;
   scoreboard  sco;

   mailbox #(transaction) g2d_mbx;
   mailbox #(transaction) m2s_mbx;
   mailbox #(transaction) d2m_mbx;

   event g2s_next;
   virtual dpll_if dif;

   function new(virtual dpll_if dif);
      g2d_mbx = new();
      m2s_mbx = new();
      d2m_mbx = new();

      gen = new(g2d_mbx);
      drv = new(g2d_mbx, d2m_mbx);

      mon = new(d2m_mbx, m2s_mbx);
      sco = new(m2s_mbx);
 
      this.dif = dif;
      drv.dif = this.dif;
      mon.dif = this.dif;

      gen.next = g2s_next;
      sco.next = g2s_next;
   endfunction

   task pre_test();
      sco.fd = $fopen("./scolog.csv", "w");
      sco.write_log_header();

      drv.reset();
   endtask

   task test();
      fork
         gen.run();
         drv.run();
         mon.run();
         sco.run();
      join_any
   endtask

   task post_test();
      wait(gen.done.triggered);
      $finish();

      $fclose(sco.fd);
   endtask

   task run();
      pre_test();
      test();
      post_test();
   endtask
endclass

module dpll_tb;
   dpll_if dif ();
   dpll dut (dif.clk, dif.reset, dif.clk_fin, dif.clk_fout, dif.clk8x_fout);

   initial begin
      dif.clk <= 0;
   end

   always #5 dif.clk <= ~dif.clk;

   environment env;

   initial begin
      env = new(dif);
      env.gen.count = 10;
      env.run();
   end

   initial begin
      $dumpfile("dump.vcd");
      $dumpvars;   
   end
endmodule

