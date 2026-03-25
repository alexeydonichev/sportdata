#!/bin/bash

psql -h localhost -U sportdata_admin -d sportdata -f /absolute/path/to/scripts/run_analytics.sql
