# Per-sub-module resources of the "reflex" hierarchy, counted from the routed design.
proc submodule_table {outfile} {
    set f [open $outfile w]
    puts $f "LUT cells count LUT primitives; Vivado packs two into one physical LUT where it can."
    puts $f [format "%-10s %9s %8s %6s %8s" sub-module "LUT cells" FFs DSPs CARRY8]
    foreach m {regs gate window divider tracker servo leds} {
        set p [get_cells -hier -filter "IS_PRIMITIVE && NAME =~ */reflex/$m/*"]
        set lut [llength [filter $p {REF_NAME =~ LUT*}]]
        set ff  [llength [filter $p {REF_NAME =~ FD*}]]
        set dsp [llength [get_cells -hier -filter "PRIMITIVE_LEVEL == MACRO && REF_NAME =~ DSP* && NAME =~ */reflex/$m/*"]]
        set cy  [llength [filter $p {REF_NAME =~ CARRY*}]]
        puts $f [format "%-10s %9d %8d %6d %8d" $m $lut $ff $dsp $cy]
    }
    close $f
}
