#!/bin/bash

maxEnabledEvents=0
sumEnabledEvents=0
maxEvents=0
sumEvents=0
maxChains=0
sumChains=0
faultyExecutions=0
nontermExecutions=0
nontermExecutionList=""
totalExecutions=0
totalTime=0

prefixEnabledEvents=", maxEnabledEvents ="
prefixEvents=", totalEvents = "
prefixChains=", maxChains ="
prefixTime=", totalTime = "
suffixTime=" ms"

for dir in $(find $1 -maxdepth 1 -type d -regex ".*/[0-9]+") ; do
  events=$(grep "$prefixEvents" $dir/statistics)
  events=${events#$prefixEvents}

  if [[ $events -eq 1000 ]]; then
    # We exclude the executions that have reached 1000 executions
    # and count them separately
    (( nontermExecutions++ ))
    nontermExecutionList="$nontermExecutionList ${dir#${dir%%[0-9]*}}"
  else
    (( $events > $maxEvents )) && (( maxEvents=$events ))
    (( sumEvents+=$events ))
  fi

  enabledEvents=$(grep "$prefixEnabledEvents" $dir/statistics)
  enabledEvents=${enabledEvents#$prefixEnabledEvents}
  (( $enabledEvents > $maxEnabledEvents )) && (( maxEnabledEvents=$enabledEvents ))
  (( sumEnabledEvents+=$enabledEvents ))

  chains=$(grep "$prefixChains" $dir/statistics)
  if [[ $chains != "" ]]; then
    chains=${chains#$prefixChains}
    (( $chains > $maxChains )) && (( maxChains=$chains ))
    (( sumChains+=$chains ))
  fi

  [[ "$(grep FAILURE $dir/statistics)" != "" ]] && (( faultyExecutions++ ))
  (( totalExecutions++ ))

  time=$(grep "$prefixTime" $dir/statistics)
  time=${time#$prefixTime}
  time=${time%$suffixTime}
  (( totalTime+=$time ))
done

avgMaxEnabledEvents=$(echo "scale=1; $sumEnabledEvents / $totalExecutions" | bc -q)
avgEvents=$(echo "scale=1; $sumEvents / ($totalExecutions - $nontermExecutions)" | bc -q)
avgMaxChains=$(echo "scale=1; $sumChains / $totalExecutions" | bc -q)

echo "Average max enabled events = $avgMaxEnabledEvents"
echo "Max enabled events         = $maxEnabledEvents"
echo "Avg events                 = $avgEvents (excluding nonterminating executions)"
echo "Max events                 = $maxEvents (excluding nonterminating executions)"
echo "Avg max chains             = $avgMaxChains"
echo "Max chains                 = $maxChains"
echo "Faulty executions          = $faultyExecutions"
if [[ $nontermExecutions -gt 0 ]]; then
  echo "Nonterminating executions  = $nontermExecutions"
  echo "List of nonterm executions =$nontermExecutionList"
fi
echo "Total executions           = $totalExecutions"
echo "Total time                 = $((totalTime/1000)) s"
