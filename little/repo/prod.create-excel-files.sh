# prod.create-excel-files.sh

#!/bin/bash

curl -H "Content-Type: application/json" -X POST -d '{}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"DS"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"TAC"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IA"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"India"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Analytics"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Communication"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Data"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Education"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Environment"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Health"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Justice"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"Technology"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"SSES","unit":"TRUE"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"GH"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"Int'"'"'l Ed"}' https://revpred.rti.org/api/excel
curl -H "Content-Type: application/json" -X POST -d '{"bu":"IDG","unit":"SG&R"}' https://revpred.rti.org/api/excel

