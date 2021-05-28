clear
echo "
List of available scripts
-------------------------

Repositories:

   - main - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - help.sh                     : This help
     - sendBucket.sh               : Send a file to the bucket

   - SQLTools - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - tbsUsage.sql                : Ocupation of tablespaces
     - fkWithoutIndexes.sql        : Find non-indexed foreign keys
     - sessionsPerService.sql      : Services used 
     - rmanProgress.sql            : Progress of RMAN jobs (WIP)

   - ASMTools - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - disksPerCell.sql            : Disks per cell (useful during patching)

   - CNAFTools  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
     - heatMapOPA.sql              : Map of OPA processing times + Network (numbers)
     - heatMapOPAPct.sql           : Map of OPA processing times + Network (percentages)
     - heatMapOPAProcessing.sql    : Map of OPA processing times (numbers)
     - heatMapOPAProcessingPct.sql : Map of OPA processing times (percentages)
   -  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Usage:
  
  runScript.sh    [repo/]scriptName    ==> Run and send output
  runScript.sh -i [repo/]scriptName    ==> Do not send output
  runScript.sh -H [repo/]scriptName    ==> HTML Output (for SQL ONLY)

" | more
