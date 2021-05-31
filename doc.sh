echo "<HTML><BODY>"
for engine in AnalyseRessources ExamenDroitAL CalculBaseRessource %
do
echo -e "\
01/01/2021;15/04/2021;$engine
24/04/2021 10:00:00;24/04/2021 18:00:00;$engine
29/05/2021 13:00:00;29/05/2021 18:00:00;$engine
" | grep -v "^#" | while read line
do
  d1=$(echo $line | cut -f1 -d";")
  d2=$(echo $line | cut -f2 -d";")
  eng=$(echo $line | cut -f3 -d";")
  echo "<H1>Period : $d1 --> $d2 (Engine : $eng)</H1>"

  echo "<H2>Percentages</H2>"
  echo "<H3>OPA Global time including Nework</H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPAGlobalTime.sql "$d1" "$d2" "$eng"
  echo "</PRE>"
  echo "<H3>OPA Processing time Without Nework</H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPAProcessingTime.sql "$d1" "$d2" "$eng"
  echo "</PRE>"
  echo "<H3>OPA Packets Size </H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPASizeIn.sql "$d1" "$d2" "$eng"
  echo "</PRE>"

  echo "<H2>Rough numbers </H2>"
  echo "<H3>OPA Global time including Nework</H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPAGlobalTime.sql "$d1" "$d2" "$eng" VALUES
  echo "</PRE>"
  echo "<H3>OPA Processing time Without Nework</H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPAProcessingTime.sql "$d1" "$d2" "$eng" VALUES
  echo "</PRE>"
  echo "<H3>OPA Packets Size </H3>"
  echo "<PRE>"
  ./runScript.sh -i -s heatMapOPASizeIn.sql "$d1" "$d2" "$eng" VALUES
  echo "</PRE>"
done
done
echo "</BODY></HTML>"
