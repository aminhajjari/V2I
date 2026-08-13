#!/bin/bash

#=======================================================================
# PRODUCTION SLURM SCRIPT - 80 Datasets with Weight Decay 
#=======================================================================

#SBATCH --account=def-arashmoh
#SBATCH --job-name=T2I_VIF_PROD
#SBATCH --nodes=1
#SBATCH --gpus-per-node=a100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=96:00:00

#SBATCH --output=/project/def-arashmoh/shahab33/Msc/Tab2Vis/job_logs/production_%A.out
#SBATCH --error=/project/def-arashmoh/shahab33/Msc/Tab2Vis/job_logs/production_%A.err

#SBATCH --mail-user=aminhajjr@gmail.com
#SBATCH --mail-type=BEGIN,END,FAIL

#=======================================================================
# Configuration
#=======================================================================
PROJECT_DIR="/project/def-arashmoh/shahab33/Msc"
TAB2IMG_DIR="$PROJECT_DIR/Tab2Vis"
DATASETS_DIR="$PROJECT_DIR/tabularDataset"
VENV_PATH="$PROJECT_DIR/venvMsc/bin/activate"
BATCH_SCRIPT="$TAB2IMG_DIR/run_all_datasets.py"
MAIN_SCRIPT="$TAB2IMG_DIR/run_vif.py"
RESULTS_BASE="$TAB2IMG_DIR/results"
JOB_LOGS_DIR="$TAB2IMG_DIR/job_logs"

TIMEOUT_DEFAULT=14400  # 4 hours (safe for most datasets)

#=======================================================================
# Job Information
#=======================================================================
echo "=========================================="
echo "TABLE2IMAGE-VIF PRODUCTION RUN"
echo "=========================================="
echo "Job ID: $SLURM_JOB_ID"
echo "Started: $(date)"
echo "Node: $(hostname)"
echo "Datasets dir: $DATASETS_DIR"
echo "Configuration:"
echo "  - Weight Decay: 1e-4 (AdamW)"
echo "  - Timeout: 4 hours per dataset"
echo "  - CPUs: 8 cores"
echo "  - Memory: 64GB"
echo "=========================================="
echo ""

#=======================================================================
# GPU Information
#=======================================================================
echo "GPU Information:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
echo ""

#=======================================================================
# Setup
#=======================================================================
echo "Creating directories..."
mkdir -p "$JOB_LOGS_DIR"
mkdir -p "$RESULTS_BASE"
echo "✅ Directories ready"
echo ""

#=======================================================================
# Verify Files
#=======================================================================
echo "Verifying environment..."

if [ ! -d "$DATASETS_DIR" ]; then
    echo "❌ ERROR: Datasets not found: $DATASETS_DIR"
    ls -la "$PROJECT_DIR" | grep -i tabular
    exit 1
fi

if [ ! -f "$BATCH_SCRIPT" ]; then
    echo "❌ ERROR: Batch script not found: $BATCH_SCRIPT"
    exit 1
fi

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "❌ ERROR: Main script not found: $MAIN_SCRIPT"
    exit 1
fi

if [ ! -f "$VENV_PATH" ]; then
    echo "❌ ERROR: Virtual env not found: $VENV_PATH"
    exit 1
fi

DATASET_COUNT=$(find "$DATASETS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "✅ Found $DATASET_COUNT dataset folders"
echo ""

#=======================================================================
# Load Environment
#=======================================================================
echo "Loading modules..."
module purge
module load StdEnv/2023
module load python/3.11
module load cuda/12.2
echo "✅ Modules loaded"
echo ""

echo "Activating virtual environment..."
source "$VENV_PATH"
echo "✅ Virtual environment active"
echo ""

echo "Python environment:"
python --version
python -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU: {torch.cuda.get_device_name(0)}')
"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Environment check failed!"
    exit 1
fi

echo "✅ Environment ready"
echo ""

#=======================================================================
# Verify Weight Decay in Code
#=======================================================================
echo "Verifying weight decay configuration..."
if grep -q "weight_decay=1e-4" "$MAIN_SCRIPT"; then
    echo "✅ Weight decay (1e-4) confirmed in run_vif.py"
else
    echo "⚠️  WARNING: weight_decay not found in run_vif.py"
    echo "   Make sure it's configured correctly!"
fi
echo ""

#=======================================================================
# Execute Batch Processing
#=======================================================================
echo "=========================================="
echo "🚀 STARTING BATCH PROCESSING"
echo "=========================================="
echo "Using updated run_all_datasets.py with:"
echo "  ✅ Weight decay documentation"
echo "  ✅ Enhanced statistics"
echo ""
echo "Running command:"
echo "python $BATCH_SCRIPT \\"
echo "  --datasets_dir $DATASETS_DIR \\"
echo "  --output_base $RESULTS_BASE \\"
echo "  --job_id $SLURM_JOB_ID \\"
echo "  --script_path $MAIN_SCRIPT \\"
echo "  --timeout $TIMEOUT_DEFAULT"
echo ""
echo "=========================================="
echo ""

# Run the batch processor
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
echo "Finished: $(date)"
echo "Exit code: $EXIT_CODE"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    RESULT_DIR=$(find "$RESULTS_BASE" -maxdepth 1 -type d -name "*_JOB${SLURM_JOB_ID}" | head -1)
    
    echo "✅ SUCCESS!"
    echo ""
    echo "📂 Results location:"
    echo "    $RESULT_DIR/"
    echo ""
    echo "📊 Files generated:"
    echo "    ├── csv/"
    echo "    │   ├── results_summary.csv"
    echo "    │   └── statistics.csv"
    echo "    ├── latex/"
    echo "    │   └── results_latex.txt"
    echo "    └── logs/"
    echo "        └── results.jsonl"
    echo ""
    
    
    if [ -f "$RESULT_DIR/csv/statistics.csv" ]; then
        echo "📊 Quick Statistics:"
        grep "Average Accuracy" "$RESULT_DIR/csv/statistics.csv" | head -1
        grep "Datasets >90%" "$RESULT_DIR/csv/statistics.csv" | head -1
    fi
    
    echo "📧 Completion email sent to: aminhajjr@gmail.com"
    echo "🎉 All $DATASET_COUNT datasets processed!"
    
else
    echo "⚠️  Some datasets may have failed"
    echo "Check logs:"
    echo "    Output: $JOB_LOGS_DIR/production_${SLURM_JOB_ID}.out"
    echo "    Error:  $JOB_LOGS_DIR/production_${SLURM_JOB_ID}.err"
fi

echo "=========================================="
exit $EXIT_CODE
