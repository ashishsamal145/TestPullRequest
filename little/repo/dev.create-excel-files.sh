# dev.create-excel-files.sh

#!/bin/bash

curl -H "Content-Type: application/json" -X POST -d '{}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"DS"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"TAC"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IA"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"India"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Analytics"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Communication"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Data"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Education"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Environment"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Health"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Justice"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Technology"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"TRUE"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"GH"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"SG&R"}' https://revpred-dev.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"Int'"'"'l Ed"}' https://revpred-dev.rti.org/api/excel
