# Copyright (c) 2014 Quanta Research Cambridge, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

set scriptsdir [file dirname [info script] ]
source $scriptsdir/log.tcl

source "board.tcl"

file mkdir $ipdir/$boardname
### logs
set commandlog "$ipdir/$boardname/command"
set errorlog "$ipdir/$boardname/critical"

set commandfilehandle [open "$commandlog.log" w]
set errorfilehandle [open "$errorlog.log" w]

proc xbsv_set_board_part {} {
    global boardname partname
    if [catch {current_project}] {
	create_project -name local_synthesized_ip -in_memory
    }
    set_property PART $partname [current_project]
}

proc fpgamake_ipcore {core_name core_version ip_name params} {
    global ipdir boardname

    ## make sure we have a project configured for the correct board
    if [catch {current_project}] {
	xbsv_set_board_part
    }

    set generate_ip 0

    if [file exists $ipdir/$boardname/$ip_name/$ip_name.xci] {
    } else {
	puts "no xci file $ip_name.xci"
	set generate_ip 1
    }
    if [file exists $ipdir/$boardname/$ip_name/vivadoversion.txt] {
	gets [open $ipdir/$boardname/$ip_name/vivadoversion.txt r] generated_version
	set current_version [version -short]
	puts "core was generated by vivado $generated_version, currently running vivado $current_version"
	if {$current_version != $generated_version} {
	    puts "vivado version does not match"
	    set generate_ip 1
	}
    } else {
	puts "no vivado version recorded"
	set generate_ip 1
    }

    ## check requested core version and parameters
    if [file exists $ipdir/$boardname/$ip_name/coreversion.txt] {
	gets [open $ipdir/$boardname/$ip_name/coreversion.txt r] generated_version
	set current_version "$core_name $core_version $params"
	puts "Core generated: $generated_version"
	puts "Core requested: $current_version"
	if {$current_version != $generated_version} {
	    puts "core version or params does not match"
	    set generate_ip 1
	}
    } else {
	puts "no core version recorded"
	set generate_ip 1
    }

    puts "generate_ip $generate_ip"
    if $generate_ip {
        puts "BEFORE generate_ip"
	file delete -force $ipdir/$boardname/$ip_name
	file mkdir $ipdir/$boardname
	log_command "create_ip -name $core_name -version $core_version -vendor xilinx.com -library ip -module_name $ip_name -dir $ipdir/$boardname" "$ipdir/$boardname/temp.log"
	set_property -dict $params [get_ips $ip_name]
        report_property -file $ipdir/$boardname/$ip_name.properties.log [get_ips $ip_name]
	
	generate_target all [get_files $ipdir/$boardname/$ip_name/$ip_name.xci]

	set versionfd [open $ipdir/$boardname/$ip_name/vivadoversion.txt w]
	puts $versionfd [version -short]
	close $versionfd

	set corefd [open $ipdir/$boardname/$ip_name/coreversion.txt w]
	puts $corefd "$core_name $core_version $params"
	close $corefd
        puts "AFTER generate_ip"
    } else {
	read_ip $ipdir/$boardname/$ip_name/$ip_name.xci
    }
    if [file exists $ipdir/$boardname/$ip_name/$ip_name.dcp] {
    } else {
	puts "RUNNING: synth_ip"
	synth_ip [get_ips $ip_name]
        #log_command "synth_design -top $ip_name -mode out_of_context" "$ipdir/$boardname/temp.log"
	puts "AFTER: synth_ip"
    }
}

proc fpgamake_altera_ipcore {core_name core_version ip_name file_set params} {
    global ipdir boardname partname

    exec -ignorestderr -- ip-generate \
            --project-directory=$ipdir/$boardname                            \
            --output-directory=$ipdir/$boardname/synthesis/$ip_name          \
            --file-set=$file_set                                             \
            --report-file=html:$ipdir/$boardname/$ip_name.html               \
            --report-file=sopcinfo:$ipdir/$boardname/$ip_name.sopcinfo       \
            --report-file=cmp:$ipdir/$boardname/$ip_name.cmp                 \
            --report-file=qip:$ipdir/$boardname/synthesis/$ip_name/$ip_name.qip       \
            --report-file=svd:$ipdir/$boardname/synthesis/$ip_name/$ip_name.svd       \
            --report-file=regmap:$ipdir/$boardname/synthesis/$ip_name/$ip_name.regmap \
            --report-file=xml:$ipdir/$boardname/$ip_name.xml                 \
            --system-info=DEVICE_FAMILY=StratixV                             \
            --system-info=DEVICE=$partname                                   \
            --system-info=DEVICE_SPEEDGRADE=2_H2                             \
            --language=VERILOG                                               \
            {*}$params\
            --component-name=$core_name                                      \
            --output-name=$ip_name
}

proc fpgamake_altera_qmegawiz {ip_path ip_name} {
	global ipdir boardname
	set generate_ip 0
	if [file exists $ipdir/$boardname/$ip_name/$ip_name.qip] {
	} else {
		puts "no qip file $ip_name.qip"
		set generate_ip 1
	}

	if $generate_ip {
		file delete -force $ipdir/$boardname/synthesis/$ip_name
		file mkdir $ipdir/$boardname/synthesis/$ip_name
		puts "generate_ip $generate_ip"
		file copy $ip_path/$ip_name.v $ipdir/$boardname/synthesis/$ip_name/$ip_name.v
		exec -ignorestderr -- qmegawiz \
			-silent \
			$ipdir/$boardname/synthesis/$ip_name/$ip_name.v
	}
}
