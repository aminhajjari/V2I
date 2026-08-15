#!/bin/bash

#=======================================================================
# PRODUCTION SLURM SCRIPT - ALL DATASETS
#=======================================================================

#SBATCH --account=def-arashmoh
#SBATCH --job-name=T2I_VIF_PROD
#SBATCH --nodes=1
#SBATCH --gpus-per-node=a100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=96:00:00

#SBATCH --output=/home/gkianfar/scratch/Amin/ICC/output/logs/production_%A.out
#SBATCH --error=/home/gkianfar/scratch/Amin/ICC/output/logs/production_%A.err

#SBATCH --mail-user=amminhajjri@gmail.com
#SBATCH --mail-type=BEGIN,END,FAIL


#=======================================================================
# Configuration
#=======================================================================

PROJECT_DIR="/home/gkianfar/scratch/Amin/ICC"

CODE_DIR="$PROJECT_DIR/main/V2I"
DATASETS_DIR="$PROJECT_DIR/Unzippeddata/CSV"

VENV_PATH="$PROJECT_DIR/venvMsc/bin/activate"

BATCH_SCRIPT="$CODE_DIR/run_all_datasets.py"
MAIN_SCRIPT="$CODE_DIR/main.py"

RESULTS_BASE="$PROJECT_DIR/output"
JOB_LOGS_DIR="$PROJECT_DIR/output/logs"

TIMEOUT_DEFAULT=14400


#=======================================================================
# Job Information
#=======================================================================

echo "=========================================="
echo "TABLE2IMAGE-VIF PRODUCTION RUN"
echo "=========================================="
echo "Job ID:       $SLURM_JOB_ID"
echo "Started:      $(date)"
echo "Node:         $(hostname)"
echo "Code dir:     $CODE_DIR"
echo "Datasets dir: $DATASETS_DIR"
echo "Output dir:   $RESULTS_BASE"
echo "=========================================="
echo ""


#=======================================================================
# Create Required Directories
#=======================================================================

echo "Creating output directories..."

mkdir -p "$JOB_LOGS_DIR"
mkdir -p "$RESULTS_BASE"

echo "Directories ready."
echo ""


#=======================================================================
# Verify Files and Directories
#=======================================================================

echo "Verifying files and directories..."

if [ ! -d "$DATASETS_DIR" ]; then
    echo "ERROR: Dataset directory not found:"
    echo "$DATASETS_DIR"
    exit 1
fi

if [ ! -f "$BATCH_SCRIPT" ]; then
    echo "ERROR: Batch script not found:"
    echo "$BATCH_SCRIPT"
    exit 1
fi

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "ERROR: Main script not found:"
    echo "$MAIN_SCRIPT"
    exit 1
fi

if [ ! -f "$VENV_PATH" ]; then
    echo "ERROR: Virtual environment not found:"
    echo "$VENV_PATH"
    exit 1
fi


#=======================================================================
# Count Datasets
#=======================================================================

DATASET_COUNT=$(find "$DATASETS_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d | wc -l)

echo "Found $DATASET_COUNT dataset folders."

if [ "$DATASET_COUNT" -eq 0 ]; then
    echo "ERROR: No datasets found!"
    exit 1
fi

echo ""


#=======================================================================
# List Datasets
#=======================================================================

echo "Datasets that will be processed:"
find "$DATASETS_DIR" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf "  - %f\n" | sort

echo ""


#=======================================================================
# Load Modules
#=======================================================================

echo "Loading modules..."

module purge
module load StdEnv/2023
module load python/3.11
module load cuda/12.2

echo "Modules loaded."
echo ""


#=======================================================================
# Activate Virtual Environment
#=======================================================================

echo "Activating virtual environment..."

source "$VENV_PATH"

echo "Virtual environment activated."
echo ""


#=======================================================================
# Python Environment Check
#=======================================================================

echo "=========================================="
echo "PYTHON ENVIRONMENT"
echo "=========================================="

which python
python --version

echo ""

echo "GPU information:"
nvidia-smi --query-gpu=name,memory.total,driver_version \
    --format=csv,noheader

echo ""

python -c "
import torch

print('PyTorch:', torch.__version__)
print('CUDA available:', torch.cuda.is_available())

if torch.cuda.is_available():
    print('CUDA version:', torch.version.cuda)
    print('GPU:', torch.cuda.get_device_name(0))
"

if [ $? -ne 0 ]; then
    echo "ERROR: Python/PyTorch environment check failed."
    exit 1
fi

echo ""
echo "Environment check passed."
echo ""


#=======================================================================
# Verify Main Code
#=======================================================================

echo "Checking main.py..."

if grep -q "weight_decay=1e-4" "$MAIN_SCRIPT"; then
    echo "Weight decay 1e-4 confirmed."
else
    echo "WARNING: weight_decay=1e-4 not found in main.py"
fi

echo ""


#=======================================================================
# Start Production Run
#=======================================================================

echo "=========================================="
echo "STARTING PRODUCTION RUN"
echo "=========================================="

echo "Number of datasets: $DATASET_COUNT"
echo "Timeout per dataset: $TIMEOUT_DEFAULT seconds"
echo ""

echo "Batch processor:"
echo "$BATCH_SCRIPT"

echo ""

echo "Main script:"
echo "$MAIN_SCRIPT"

echo ""

echo "Dataset directory:"
echo "$DATASETS_DIR"

echo ""

echo "Output directory:"
echo "$RESULTS_BASE"

echo ""
echo "=========================================="
echo ""


#=======================================================================
# Run ALL DATASETS
#=======================================================================

cd "$CODE_DIR" || {
    echo "ERROR: Cannot enter code directory."
    exit 1
}

python "$BATCH_SCRIPT" \
    --datasets_dir "$DATASETS_DIR" \
    --output_base "$RESULTS_BASE" \
    --job_id "$SLURM_JOB_ID" \
    --script_path "$MAIN_SCRIPT" \
    --timeout "$TIMEOUT_DEFAULT"

EXIT_CODE=$?


#=======================================================================
# Final Summary
#=======================================================================

echo ""
echo "=========================================="
echo "PRODUCTION RUN COMPLETE"
echo "=========================================="

echo "Finished:  $(date)"
echo "Exit code: $EXIT_CODE"
echo "Datasets:  $DATASET_COUNT"
echo ""


if [ "$EXIT_CODE" -eq 0 ]; then

    echo "SUCCESS!"
    echo ""

    RESULT_DIR=$(find "$RESULTS_BASE" \
        -maxdepth 1 \
        -type d \
        -name "*_JOB${SLURM_JOB_ID}" \
        | head -1)

    echo "Results directory:"
    echo "$RESULT_DIR"
    echo ""

    if [ -n "$RESULT_DIR" ] && [ -d "$RESULT_DIR" ]; then

        echo "Generated files:"
        find "$RESULT_DIR" -maxdepth 2 -type f | sort

        echo ""

        if [ -f "$RESULT_DIR/csv/statistics.csv" ]; then
            echo "Statistics:"
            cat "$RESULT_DIR/csv/statistics.csv"
        fi

    fi

else

    echo "WARNING: Batch processing returned exit code $EXIT_CODE"
    echo ""
    echo "Some datasets may have failed."
    echo ""
    echo "Check SLURM logs:"
    echo "$JOB_LOGS_DIR/production_${SLURM_JOB_ID}.out"
    echo "$JOB_LOGS_DIR/production_${SLURM_JOB_ID}.err"

fi

echo ""
echo "=========================================="

exit "$EXIT_CODE"
