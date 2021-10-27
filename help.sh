clear
echo "
List of available scripts
-------------------------

Repositories:

   - main - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - help.sh                      : This help
     - sendBucket.sh                : Send a file to the bucket

   - SQLTools - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - tbsUsage.sql                 : Ocupation of tablespaces
     - fkWithoutIndexes.sql         : Find non-indexed foreign keys
     - sessionsPerService.sql       : Services used 
     - rmanProgress.sql             : Progress of RMAN jobs (WIP)

   - ASMTools - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - disksPerCell.sql             : Disks per cell (useful during patching)
     - ASMMap.sql                   : Shows disk groups cnts a   :d size

   - CNAFTools  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - heatMapOPAGlobalTime.sql     : Map of OPA processing times (including network VALUES & PERCENTAGES)
     - heatMapOPAProcessingTime.sql : Map of OPA processing times (without network VALUES & PERCENTAGES)
     - heatMapOPASizeIn.sql         : Map of OPA packets size (to OPA VALUES & PERCENTAGES)
     - OPACallsPerMinute.sql        : Extacts OPA Calls/Cases/Response times per interval
     - OPABatchProgress.sql         : Shows number of cases and error rate (globally or per hour)
     - analyseHISTO.sql             : Lists tables with HISTOGRAMS
   -  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Usage:
  
  runScript.sh    [repo/]scriptName    ==> Run and send output
  runScript.sh -i [repo/]scriptName    ==> Do not send output
  runScript.sh -H [repo/]scriptName    ==> HTML Output (for SQL ONLY)

To update runScripts : 
  bash -c \"set runScript ; \$(curl -sL https://raw.githubusercontent.com/mbottion/main/main/getMain.sh)\"
  
" | more
