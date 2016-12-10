#!/bin/bash

function load_capacity_visualization()
{
    cat << __END__OF__VISUALIZATION__BEGIN__
    <!--Load the AJAX API-->
    <script type="text/javascript" src="http://www.google.com/jsapi"></script>
    <script type="text/javascript">
    
      // Load the Visualization API and the piechart package.
      google.load('visualization', '1', {'packages':['piechart']});
      google.load('visualization', '1', {'packages':['columnchart']});
      google.load('visualization', '1', {'packages':['barchart']});
      
      // Set a callback to run when the API is loaded.
      google.setOnLoadCallback(drawChart);
      
      // Callback that creates and populates a data table, 
      // instantiates the pie chart, passes in the data and
      // draws it.
      function drawChart() {
      var used_raw_capacity = new google.visualization.DataTable();
      var unused_raw_capacity = new google.visualization.DataTable();
      var total_raw_capacity = new google.visualization.DataTable();

      var raidset_capacity = new google.visualization.DataTable();
      var vglv_capacity = new google.visualization.DataTable();
      var expvol_capacity = new google.visualization.DataTable();

      used_raw_capacity.addColumn('string', 'Disk');
      used_raw_capacity.addColumn('number', 'Capacity in MB');
      unused_raw_capacity.addColumn('string', 'Disk');
      unused_raw_capacity.addColumn('number', 'Capacity in MB');
      total_raw_capacity.addColumn('string', 'Type');
      total_raw_capacity.addColumn('number', 'Capacity in MB');

      raidset_capacity.addColumn('string', 'Raidset');
      raidset_capacity.addColumn('number', 'User');
      raidset_capacity.addColumn('number', 'Parity');

      expvol_capacity.addColumn('string', 'Exported Vol');
      expvol_capacity.addColumn('number', 'Capacity in MB');
__END__OF__VISUALIZATION__BEGIN__
    
    shift
    echo "used_raw_capacity.addRows($1);"
    shift
    local -i i_i=0
    local -i used_cap=0
    local lastraid=""
    local cur_vg=""
    local last_vg=""
    local -i lvol=0
    local -i cur_lvol=""
    local -i max_lvol=""

    while [ "$1" != "Unused" ]
    do
	echo "used_raw_capacity.setValue($i_i, 0, '$1');"
	echo "used_raw_capacity.setValue($i_i, 1, $2);"
	i_i=$i_i+1
	used_cap=${used_cap}+$2
	shift 2
    done

    shift
    echo "unused_raw_capacity.addRows($1);"
    local -i unused_cap=0
    shift
    i_i=0
    while [ "$1" != "Raidsets" ] && [ -n "$1" ]
    do
	echo "unused_raw_capacity.setValue($i_i, 0, '$1');"
	echo "unused_raw_capacity.setValue($i_i, 1, $2);"
	i_i=$i_i+1
	unused_cap=${unused_cap}+$2
	shift 2
    done
    echo "total_raw_capacity.addRows(2);"
    echo "total_raw_capacity.setValue(0, 0, 'Used');"
    echo "total_raw_capacity.setValue(0, 1, ${used_cap});"
    echo "total_raw_capacity.setValue(1, 0, 'Unused');"
    echo "total_raw_capacity.setValue(1, 1, ${unused_cap});"
    if [ "$1" = "Raidsets" ]
    then
	i_i=0
	shift
	echo "raidset_capacity.addRows($1);"
	shift
	while [ "$1" != "VGS" ] && [ -n "$1" ]
	do
	    lastraid=`echo $1 | awk -F '-' '{print $1}'`
	    echo "raidset_capacity.setValue($i_i, 0, '$lastraid');"
	    echo "raidset_capacity.setValue($i_i, 1, $2);"
	    if [ "$4" != "0" ]
	    then
		echo "raidset_capacity.setValue($i_i, 2, $4);"
	    fi
	    i_i=$i_i+1
	    shift 4
	done
    fi
    if [ "$1" = "VGS" ]
    then
	i_i=-1
	shift
	echo "vglv_capacity.addColumn('string', 'VG');"
	max_lvol=$2
	echo "//DEBUG: max_lvol: $2"
	while [ "$lvol" -lt "$2" ]
	do
	    echo "vglv_capacity.addColumn('number', 'lvol$lvol');"
	    lvol=$lvol+1
	done
	echo "vglv_capacity.addColumn('number', 'Free');"
	echo "vglv_capacity.addRows($1);"
	shift 2
	while [ "$1" != "EXPVOL" ] && [ -n "$1" ]
	do
	    cur_vg=`echo $1 | awk -F '/' '{print $1}'`
	    if [ "$cur_vg" != "$last_vg" ]
	    then
		last_vg=$cur_vg
		i_i=$i_i+1
		echo "vglv_capacity.setValue($i_i, 0, '$cur_vg');"
		echo "vglv_capacity.setValue($i_i, $max_lvol+1, $2);"
		cur_lvol=1
	    else
		echo "vglv_capacity.setValue($i_i, $cur_lvol, $2);"
		cur_lvol=$cur_lvol+1
	    fi
	    shift 2
	done
    fi
    if [ "$1" = "EXPVOL" ]
    then
	i_i=0
	shift
	echo "expvol_capacity.addRows($1);"
	echo "//DEBUG: expvol_row_capacity: $1"
	shift
	while [ -n "$1" ]
	do
	    echo "expvol_capacity.setValue($i_i, 0, '$1');"
	    echo "expvol_capacity.setValue($i_i, 1, $2);"
	    i_i=$i_i+1
	    shift 2
	done
    fi
    cat << __END__OF__VISUALIZATION__END__
        var used_raw_capacity_chart = new google.visualization.ColumnChart(document.getElementById('used_raw_capacity_chart_div'));
        used_raw_capacity_chart.draw(used_raw_capacity, {width: 550, height: 200, is3D: true, legend: 'none', min:'0'});
        var unused_raw_capacity_chart = new google.visualization.ColumnChart(document.getElementById('unused_raw_capacity_chart_div'));
        unused_raw_capacity_chart.draw(unused_raw_capacity, {width: 550, height: 200, is3D: true, legend: 'none', min:'0'});
        var total_raw_capacity_chart = new google.visualization.PieChart(document.getElementById('total_raw_capacity_chart_div'));
        total_raw_capacity_chart.draw(total_raw_capacity, {width: 550, height: 200, is3D: true});

        var raidset_capacity_chart = new google.visualization.ColumnChart(document.getElementById('raidset_capacity_chart_div'));
        raidset_capacity_chart.draw(raidset_capacity, {width: 550, height: 200, is3D: true, isStacked: true, legend: 'bottom', min:'0'});

        var vglv_capacity_chart = new google.visualization.ColumnChart(document.getElementById('vglv_capacity_chart_div'));
        vglv_capacity_chart.draw(vglv_capacity, {width: 550, height: 200, is3D: true, isStacked: true, legend: 'bottom', min:'0'});
        var expvol_capacity_chart = new google.visualization.BarChart(document.getElementById('expvol_capacity_chart_div'));
        expvol_capacity_chart.draw(expvol_capacity, {width: 550, height: 200, is3D: true, legend: 'none', min:'0'});
      }
    </script>
__END__OF__VISUALIZATION__END__
}
