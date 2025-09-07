# HeartScanner Clinical Evaluation Guide

## Overview
This guide helps doctors evaluate the EF and Segmentation model performance before final deployment. The app includes comprehensive debugging, validation, and performance tracking features.

## Key Clinical Features Already Built-In

### 1. Real-Time Model Performance Monitoring
- **EF Model Validation**: Physiological range validation (15-80%)
- **Segmentation Quality Checks**: Automatic mask validation
- **Processing Time Tracking**: All inference times logged
- **Confidence Scores**: Available for all predictions
- **Clinical Alerts**: Automatic warnings for out-of-range values

### 2. Comprehensive Logging System
The app provides detailed console output for clinical evaluation:

#### EF Model Logging:
```
🔍 EF Model - Raw output value: 0.652
🔍 EF Model - Output array shape: [1]
🔍 EF Model - Output data type: Float32
EF Model - Normalized EF: 65.2%
CLINICAL EF RESULT: 65.2% (Source: Clinical AI Model)
```

#### Segmentation Model Logging:
```
CLINICAL SEGMENTATION: Preprocessing frame...
CLINICAL SEGMENTATION: Frame preprocessed successfully, running AI model...
CLINICAL SEGMENTATION: AI model prediction successful, validating mask...
CLINICAL SEGMENTATION: ✅ Valid cardiac segmentation generated and displayed!
```

### 3. Clinical Validation Features
- **Physiological Range Checking**: EF values outside 15-80% trigger alerts
- **Frame Quality Validation**: Minimum 8 frames required for reliable EF analysis
- **Model Availability Checks**: Critical errors if models fail to load
- **Input Shape Validation**: Ensures correct data format for models

## Clinical Testing Protocol

### Phase 1: Model Loading Verification
1. **Launch App**: Check console for model loading messages
2. **Verify Models**: Look for "Successfully loaded EF_Model.mlpackage" and "Successfully loaded SegmentationModel.mlpackage"
3. **Check Compute Units**: Confirm "cpuAndNeuralEngine" for optimal performance

### Phase 2: EF Model Accuracy Testing
1. **Scan Known Cases**: Use patients with known EF values
2. **Monitor Console Output**: 
   - Raw model output values
   - Normalized EF percentages
   - Processing times
   - Confidence scores
3. **Document Results**: Compare AI predictions with ground truth

### Phase 3: Segmentation Model Evaluation
1. **Visual Assessment**: Compare AI segmentation with manual annotations
2. **Quality Validation**: Check for "Valid cardiac segmentation" messages
3. **Failure Analysis**: Note when segmentation quality checks fail

### Phase 4: Performance Metrics Collection
1. **Processing Times**: Monitor inference speed (target: <3 seconds)
2. **Frame Requirements**: Test with different frame counts
3. **Thermal Performance**: Monitor device temperature during extended use

## Key Metrics to Track

### EF Model Performance
- **Accuracy**: Compare predictions vs. ground truth
- **Precision**: Consistency across multiple scans of same patient
- **Processing Time**: Average inference time per prediction
- **Confidence Correlation**: How confidence scores relate to accuracy

### Segmentation Model Performance
- **Dice Coefficient**: Overlap with manual segmentations
- **Visual Quality**: Clinical acceptability of masks
- **Failure Rate**: Percentage of failed quality checks
- **Processing Speed**: Real-time performance assessment

## Built-In Evaluation Tools

### 1. Scan Detail View
- Shows confidence scores for each prediction
- Displays AI model version and processing time
- Color-coded EF results (Green: >55%, Orange: 40-55%, Red: <40%)

### 2. Export Functionality
- Detailed analysis reports with all metrics
- DICOM-compatible export for integration with hospital systems
- PDF reports for clinical documentation

### 3. Console Debugging
- Comprehensive logging of all model operations
- Input/output shape validation
- Performance timing information
- Error tracking and reporting

## Clinical Validation Checklist

### Before Each Testing Session:
- [ ] Verify both models loaded successfully
- [ ] Check device thermal state
- [ ] Confirm probe connectivity
- [ ] Review patient consent for AI analysis

### During Testing:
- [ ] Monitor console output for errors
- [ ] Document processing times
- [ ] Note any clinical alerts
- [ ] Compare results with clinical assessment

### After Each Session:
- [ ] Export scan data for analysis
- [ ] Document any model failures
- [ ] Note performance degradation
- [ ] Review confidence score patterns

## Expected Performance Benchmarks

### EF Model:
- **Accuracy**: >90% within ±5% of ground truth
- **Processing Time**: <2 seconds per prediction
- **Confidence**: >85% for clinically acceptable results

### Segmentation Model:
- **Dice Score**: >0.85 for left ventricle
- **Processing Time**: <1 second per frame
- **Quality Pass Rate**: >95% for good quality images

## Troubleshooting Common Issues

### Model Loading Failures:
- Check bundle contains .mlpackage files
- Verify iOS version compatibility
- Monitor memory usage during loading

### Poor EF Accuracy:
- Ensure adequate frame count (≥8 frames)
- Check image quality and probe positioning
- Verify cardiac view is appropriate

### Segmentation Failures:
- Confirm proper cardiac view
- Check for motion artifacts
- Verify adequate contrast

## Clinical Documentation

The app automatically generates comprehensive clinical documentation including:
- Patient demographics
- Scan parameters and settings
- AI model predictions with confidence scores
- Processing times and performance metrics
- Clinical notes and observations

This documentation supports clinical validation and regulatory compliance requirements.
