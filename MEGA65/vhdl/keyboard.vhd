----------------------------------------------------------------------------------
-- ZX-Uno port for MEGA65
--
-- Keyboard driver which includes the mapping of the MEGA 65 keys to ZX Uno keys
--
-- Terminology: CS = Spectrum's CAPS SHIFT    (MEGA65's right shift key)
--              SS = Spectrum's SYMBOL SHIFT  (MEGA65 key)
--              Convencience Shift Key        (MEGA65's left shift key)
--
-- The keyboard mapping includes a "Convenience Shift Key", which is meant to
-- simplify entering special characters. The MEGA65's left shift key is the
-- convenience shift key and the right shift key is the Spectrum's CAPS SHIFT.
-- Example: When pressing the Convenience Shift + 2, then the keyboard driver
-- will generate SS + P to generate " (double quotes), because this is what you
-- would expect when looking at the MEGA65 keyboard.
--
-- If you want the native Spectrrum behavior, then you use the MEGA65's right
-- shift key, which is always mapped to be the CAPS SHIFT.
--
-- The machine is based on Miguel Angel Rodriguez Jodars ZX-Uno (Artix version)
-- MEGA65 port done by sy2002 in 2020 and licensed under GPL v3
-- Keyboard mapping as defined by Andrew Owen in December 2020
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keyboard is
port (
   clk         : in std_logic;
       
   -- interface to the MEGA65 keyboard controller       
   kio8        : out std_logic;        -- clock to keyboard
   kio9        : out std_logic;        -- data output to keyboard
   kio10       : in std_logic;         -- data input from keyboard
      
   -- interface to ZXUNO's internal logic
   row_select  : in std_logic_vector(7 downto 0);
   col_data    : out std_logic_vector(4 downto 0)
);
end keyboard;

architecture beh of keyboard is

signal matrix_col          : std_logic_vector(7 downto 0);
signal matrix_col_idx      : integer range 0 to 9 := 0;
signal key_num             : integer range 0 to 79;
signal key_status_n        : std_logic;

-- special key handling
signal bucky_key           : std_logic_vector(6 downto 0);
signal key_shift_left      : std_logic;
signal key_shift_right     : std_logic;
signal key_ctrl            : std_logic;
signal key_mega            : std_logic;


type matrix_reg_t is array(0 to 7) of std_logic_vector(4 downto 0);
signal matrix : matrix_reg_t := (others => "11111");

-- Remeber, if a certain matrix key has been set automatically as a key combo so that the raw keyscan will not delete it later.
-- Example: Consider "Inst/Del", which is mapped to "Inv. Video" aka CS+4: As "Inst/Del" is key_num zero, it would activate
-- CS and "4" at the 0th iteration. Now "4" is at the 11th iteration and would reset "4" back to "not pressed". This is why
-- we need to remember, that we did autoset this key combo by "and-ing" the autoset status to what we receive from
-- the MEGA keyboard. "And-ing" due to the negativ-active logic.
signal autoset_u : matrix_reg_t := (others => "11111");
signal autoset_m : std_logic_vector(79 downto 0) := (others => '1');

type mapping_record_t is record
   first_active   : boolean;
   first_row      : integer range 0 to 7;
   first_col      : integer range 0 to 5;
   second_active  : boolean;
   second_row     : integer range 0 to 7;
   second_col     : integer range 0 to 5;
end record;

type mapping_t is array(0 to 79) of mapping_record_t;

constant mapping : mapping_t := (         -- MEGA 65        => ZX Uno
   0  => (true,   0, 0, true,   3, 3),    -- Inst/Del       => Inv. Video: CS + 4
   1  => (true,   6, 0, false,  0, 0),    -- Return         => Enter
   2  => (true,   0, 0, true,   4, 2),    -- Cursor Right   => Cursor Right: CS + 8
   3  => (false,  0, 0, false,  0, 0),      
   4  => (false,  0, 0, false,  0, 0),      
   5  => (false,  0, 0, false,  0, 0),      
   6  => (false,  0, 0, false,  0, 0),      
   7  => (true,   0, 0, true,   4, 4),    -- Cursor Down    => Cursor Down: CS + 6    
   8  => (true,   3, 2, false,  0, 0),    -- 3              => 3      
   9  => (true,   2, 1, false,  0, 0),    -- W              => W    
   10 => (true,   1, 0, false,  0, 0),    -- A              => A     
   11 => (true,   3, 3, false,  0, 0),    -- 4              => 4      
   12 => (true,   0, 1, false,  0, 0),    -- Z              => Z      
   13 => (true,   1, 1, false,  0, 0),    -- S              => S      
   14 => (true,   2, 2, false,  0, 0),    -- E              => E      
   15 => (false,  0, 0, false,  0, 0),      
   16 => (true,   3, 4, false,  0, 0),    -- 5              => 5      
   17 => (true,   2, 3, false,  0, 0),    -- R              => R      
   18 => (true,   1, 2, false,  0, 0),    -- D              => D      
   19 => (true ,  4, 4, false,  0, 0),    -- 6              => 6      
   20 => (true,   0, 3, false,  0, 0),    -- C              => C      
   21 => (true,   1, 3, false,  0, 0),    -- F              => F      
   22 => (true,   2, 4, false,  0, 0),    -- T              => T      
   23 => (true,   0, 2, false,  0, 0),    -- X              => X      
   24 => (true ,  4, 3, false,  0, 0),    -- 7              => 7      
   25 => (true,   5, 4, false,  0, 0),    -- Y              => Y      
   26 => (true,   1, 4, false,  0, 0),    -- G              => G      
   27 => (true ,  4, 2, false,  0, 0),    -- 8              => 8      
   28 => (true ,  7, 4, false,  0, 0),    -- B              => B
   29 => (true,   6, 4, false,  0, 0),    -- H              => H      
   30 => (true,   5, 3, false,  0, 0),    -- U              => U      
   31 => (true,   0, 4, false,  0, 0),    -- V              => V      
   32 => (true ,  4, 1, false,  0, 0),    -- 9              => 9      
   33 => (true ,  5, 2, false,  0, 0),    -- I              => I      
   34 => (true,   6, 3, false,  0, 0),    -- J              => J      
   35 => (true,   4, 0, false,  0, 0),    -- 0              => 0    
   36 => (true,   7, 2, false,  0, 0),    -- M              => M
   37 => (true,   6, 2, false,  0, 0),    -- K              => K      
   38 => (true,   5, 1, false,  0, 0),    -- O              => O  
   39 => (true,   7, 3, false,  0, 0),    -- N              => N      
   40 => (true,   7, 1, true,   6, 2),    -- +              => +: SS + K       
   41 => (true,   5, 0, false,  0, 0),    -- P              => P     
   42 => (true,   6, 1, false,  0, 0),    -- L              => L      
   43 => (true,   7, 1, true,   6, 3),    -- -              => -: SS + J
   44 => (true,   7, 1, true,   7, 2),    -- .              => .: SS + M      
   45 => (true,   7, 1, true,   0, 1),    -- :              => :: SS + Z      
   46 => (true,   7, 1, true ,  3, 1),    -- @              => @: SS + 2      
   47 => (true,   7, 1, true,   7, 3),    -- ,              => ,: SS + N     
   48 => (true,   7, 1, true,   0, 2),    -- British Pound  => British Pound: SS + X      
   49 => (true,   7, 1, true,   7, 4),    -- *              => *: SS + B      
   50 => (true,   7, 1, true,   5, 1),    -- ;              => ;: SS + O      
   51 => (true,   0, 0, true,   3, 2),    -- Clr/Home       => True Video: CS + 3     
   52 => (true,   0, 0, false,  0, 0),    -- Right Shift    => Caps Shift (CS)    
   53 => (true,   7, 1, true,   6, 1),    -- =              => =: SS + L      
   54 => (true,   7, 1, true,   6, 4),    -- Arrow-up       => Arrow up: SS + H      
   55 => (true,   7, 1, true,   0, 4),    -- /              => /: SS + V         
   56 => (true,   3, 0, false,  0, 0),    -- 1              => 1
   57 => (true,   0, 0, true ,  4, 0),    -- Arrow-left     => Delete: CS + 0          
   58 => (true,   0, 0, true,   7, 1),    -- Ctrl           => Extend Mode: CS + SS       
   59 => (true ,  3, 1, false,  0, 0),    -- 2              => 2      
   60 => (true,   7, 0, false,  0, 0),    -- Space          => Space      
   61 => (true,   7, 1, false,  0, 0),    -- Mega65         => Symbol Shift (SS)   
   62 => (true,   2, 0, false,  0, 0),    -- Q              => Q    
   63 => (false,  0, 0, false,  0, 0),      
   64 => (false,  0, 0, false,  0, 0),      
   65 => (true,   0, 0, true ,  3, 0),    -- Tab            => Edit: CS + 1      
   66 => (false,  0, 0, false,  0, 0),      
   67 => (false,  0, 0, false,  0, 0),      
   68 => (false,  0, 0, false,  0, 0),      
   69 => (false,  0, 0, false,  0, 0),      
   70 => (false,  0, 0, false,  0, 0),      
   71 => (false,  0, 0, false,  0, 0),      
   72 => (false,  0, 0, false,  0, 0),      
   73 => (true,   0, 0, true,   4, 3),    -- Cursor Up      => Cursor Up: CS + 7      
   74 => (true,   0, 0, true,   3, 4),    -- Cursor Left    => Cursor Left: CS + 5      
   75 => (true,   0, 0, true,   7, 0),    -- Restore        => Break: CS + Space   
   76 => (false,  0, 0, false,  0, 0),      
   77 => (false,  0, 0, false,  0, 0),      
   78 => (false,  0, 0, false,  0, 0),      
   79 => (false,  0, 0, false,  0, 0)   
);

begin

   key_shift_left    <= bucky_key(0);
   key_shift_right   <= bucky_key(1);
   key_ctrl          <= bucky_key(2);
   key_mega          <= bucky_key(3);

   m65driver : entity work.mega65kbd_to_matrix
   port map
   (
       ioclock          => clk,
      
       flopmotor        => '0',
       flopled          => '0',
       powerled         => '1',    
       
       kio8             => kio8,
       kio9             => kio9,
       kio10            => kio10,
      
       matrix_col       => matrix_col,
       matrix_col_idx   => matrix_col_idx       
   );
   
   m65matrix_to_keynum : entity work.matrix_to_keynum
   generic map
   (
      scan_frequency    => 1000,
      clock_frequency   => 28000000      
   )
   port map
   (
      clk               => clk,
      reset_in          => '0',

      matrix_col => matrix_col,
      matrix_col_idx => matrix_col_idx,
      
      m65_key_num => key_num,
      m65_key_status_n => key_status_n,
      
      suppress_key_glitches => '1',
      suppress_key_retrigger => '0',
      
      bucky_key => bucky_key      
   );
   
   matrix_col_idx_handler : process(clk)
   begin
      if rising_edge(clk) then
         if matrix_col_idx < 9 then
           matrix_col_idx <= matrix_col_idx + 1;
         else
           matrix_col_idx <= 0;
         end if;      
      end if;
   end process;      
   
   -- fill the matrix registers that will be read by the ZX Uno
   -- support two ZX Uno matrix entries per pressed MEGA key for the end user's convenience
   write_matrix : process(clk)
   variable m : mapping_record_t;
   begin
      if rising_edge(clk) then
         m := mapping(key_num);
         if m.first_active then
            matrix(m.first_row)(m.first_col)          <= key_status_n and autoset_u(m.first_row)(m.first_col);
         end if; 
         if m.second_active then
            -- set a key and remember it as being auto-set, because we are in second_active mode
            if key_status_n = '0' then
               autoset_u(m.first_row)(m.first_col)    <= '0';
               autoset_u(m.second_row)(m.second_col)  <= '0';
               autoset_m(key_num)                     <= '0';
               matrix(m.second_row)(m.second_col)     <= '0';               
            end if;
            
            -- only unset a key in the ZX Uno matrix in second_active mode, if we did auto-set it
            if key_status_n = '1' and autoset_m(key_num) = '0' then
               autoset_u(m.first_row)(m.first_col)    <= '1';
               autoset_u(m.second_row)(m.second_col)  <= '1';
               autoset_m(key_num)                     <= '1';
               matrix(m.second_row)(m.second_col)     <= '1';
            end if;                        
         end if;
      end if;
   end process;
   
   read_matrix : process(row_select)
   begin
      case row_select is
         when "11111110" => col_data <= matrix(0);
         when "11111101" => col_data <= matrix(1);
         when "11111011" => col_data <= matrix(2);
         when "11110111" => col_data <= matrix(3);
         when "11101111" => col_data <= matrix(4);
         when "11011111" => col_data <= matrix(5);
         when "10111111" => col_data <= matrix(6);
         when "01111111" => col_data <= matrix(7);
         when others => col_data <= "11111";
      end case;
   end process;
      
end beh;
