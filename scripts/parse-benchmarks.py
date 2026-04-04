#!/usr/bin/env python3

import json
import sys
import glob
import plistlib
from pathlib import Path

def parse_xcresult(xcresult_path):
    """Parse benchmark results from .xcresult bundle"""
    results = []
    
    # Find the TestSummaries.plist file
    summaries = glob.glob(f"{xcresult_path}/**/TestSummaries.plist", recursive=True)
    
    if not summaries:
        print(f"No TestSummaries.plist found in {xcresult_path}")
        return results
    
    summary_path = summaries[0]
    
    with open(summary_path, 'rb') as f:
        plist = plistlib.load(f)
    
    # Extract test results
    for testable in plist.get('testableSummaries', []):
        for test in testable.get('tests', []):
            if test.get('testName', '').startswith('Performance'):
                for subtest in test.get('subtests', []):
                    result = {
                        'name': subtest.get('name', ''),
                        'status': subtest.get('testStatus', 'Unknown'),
                        'duration': subtest.get('duration', 0),
                        'metrics': {}
                    }
                    
                    # Extract performance metrics
                    for metric in subtest.get('performanceMetrics', []):
                        metric_name = metric.get('name', '')
                        metric_value = metric.get('measurements', [])
                        
                        if metric_value:
                            result['metrics'][metric_name] = {
                                'value': sum(metric_value) / len(metric_value),
                                'unit': metric.get('unit', ''),
                                'samples': len(metric_value)
                            }
                    
                    results.append(result)
    
    return results

def main():
    if len(sys.argv) < 3:
        print("Usage: python parse-benchmarks.py --input <xcresult_path> --output <json_path>")
        sys.exit(1)
    
    input_path = sys.argv[sys.argv.index('--input') + 1]
    output_path = sys.argv[sys.argv.index('--output') + 1]
    
    # Find all .xcresult bundles
    xcresults = glob.glob(f"{input_path}/*.xcresult")
    
    all_results = []
    
    for xcresult in xcresults:
        print(f"Parsing {xcresult}")
        results = parse_xcresult(xcresult)
        all_results.extend(results)
    
    # Create summary report
    summary = {
        'timestamp': Path.cwd().as_posix(),
        'total_tests': len(all_results),
        'passed': sum(1 for r in all_results if r['status'] == 'Success'),
        'failed': sum(1 for r in all_results if r['status'] == 'Failure'),
        'results': all_results
    }
    
    # Calculate averages
    if all_results:
        avg_duration = sum(r['duration'] for r in all_results) / len(all_results)
        summary['average_duration'] = avg_duration
    
    # Write output
    with open(output_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\nBenchmark Summary:")
    print(f"  Total tests: {summary['total_tests']}")
    print(f"  Passed: {summary['passed']}")
    print(f"  Failed: {summary['failed']}")
    
    if 'average_duration' in summary:
        print(f"  Average duration: {summary['average_duration']:.2f}s")
    
    print(f"\nResults saved to: {output_path}")

if __name__ == '__main__':
    main()
