# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pytest

import comstockpostproc.comstock
import comstockpostproc.cbecs


def test_comstock_vs_cbecs_2012():
    comstock = comstockpostproc.comstock.ComStock(
        s3_base_dir='comstock-core/test',  # If run not on S3, download results_up**.parquet manually
        comstock_run_name='com_os340_stds_030_10k_test_1',  # Name of the run on S3
        comstock_run_version='com_os340_stds_030_10k_test_1',  # Use whatever you want to see in plot and folder names
        comstock_year=2018,  # Typically don't change this
        truth_data_version='v01',  # Typically don't change this
        buildstock_csv_name='buildstock.csv',  # Download buildstock.csv manually
        acceptable_failure_percentage=0.10,  # Can increase this when testing and high failure are OK
        drop_failed_runs=True,  # False if you want to evaluate which runs failed in raw output data
        color_hex='#0072B2',  # Color used to represent this run in plots
        skip_missing_columns=True,  # False if you want to ensure you have all data specified for export
        reload_from_csv=False, # True if CSV already made and want faster reload times
        include_upgrades=False,  # False if not looking at upgrades
        upgrade_ids_to_skip=[]  # Use ['01', '03'] etc. to exclude certain upgrades
        )

    # Scale ComStock to CBECS 2012 AND remove non-ComStock buildings from CBECS
    cbecs = comstockpostproc.cbecs.CBECS(
        cbecs_year=2012,
        truth_data_version='v01',
        color_hex='#009E73',
        reload_from_csv=False
        )

    comstock.add_national_scaling_weights(cbecs, remove_non_comstock_bldg_types_from_cbecs=True)

    # Check the total square footage against published EIA tabulations
    # ComStock should be at ~64% for energy and floor area
    # https://www.eia.gov/consumption/commercial/data/2012/bc/cfm/b7.php
    wt_area_col = cbecs.col_name_to_weighted(cbecs.FLR_AREA)
    eia_sqft = 87_093_000_000
    #         108_411_136_035
    total_sqft = comstock.data[wt_area_col].sum()
    print(f'CBECS weighted area after removing comstock building types: {total_sqft}')
    # assert total_sqft == pytest.approx(eia_sqft * 0.62, rel=0.01)

    # Total square footage of ComStock and CBECS datsets should match
    # because CBECS has had non-ComStock building types removed
    cbecs_total_sqft = cbecs.data[wt_area_col].sum()
    assert cbecs_total_sqft == pytest.approx(total_sqft, rel=0.001)

    # Total weighted area of each building type, CBECS
    wtd_cbecs_areas = cbecs.data[[wt_area_col, cbecs.BLDG_TYPE]].groupby([cbecs.BLDG_TYPE]).sum()
    wtd_comstock_areas = comstock.data[[wt_area_col, comstock.BLDG_TYPE]].groupby([comstock.BLDG_TYPE]).sum()
    wtd_comstock_areas = wtd_comstock_areas.to_pandas().set_index(cbecs.BLDG_TYPE)

    # print(wtd_cbecs_areas)
    # print('')
    # print(wtd_comstock_areas)

    # Check total square footage, should match CBECS by building type
    for bldg_type in comstock.data[comstock.BLDG_TYPE].unique():
        cbecs_area = wtd_cbecs_areas[wt_area_col][bldg_type]
        comstock_area = wtd_comstock_areas[wt_area_col][bldg_type]
        assert comstock_area == pytest.approx(cbecs_area, rel=0.001), f'Weighted area for {bldg_type} does not match'

    # Check for self-consistency in weighted and unweighted energy
    engy_tol = 0.001

    # Pairs of total column and list of corresponding enduse columns
    tot_col_enduse_cols = [
        [comstock.ANN_TOT_GAS_KBTU, comstock.COLS_GAS_ENDUSE],  # Total natural gas vs. sum of end uses
        [comstock.ANN_TOT_ELEC_KBTU, comstock.COLS_ELEC_ENDUSE],  # Total electricity vs. sum of end uses
        [comstock.ANN_TOT_ENGY_KBTU, [comstock.ANN_TOT_ELEC_KBTU,  # Total energy vs. sum of all fuels
                                        comstock.ANN_TOT_GAS_KBTU,
                                        comstock.ANN_TOT_OTHFUEL_KBTU,
                                        comstock.ANN_TOT_DISTHTG_KBTU,
                                        comstock.ANN_TOT_DISTCLG_KBTU]]
    ]

    for tot_col, enduse_cols in tot_col_enduse_cols:
        # Unweighted
        sum_tot_col = comstock.data.get_column(tot_col).sum()
        sum_enduses = 0
        for c in enduse_cols:
            sum_enduses += comstock.data.get_column(c).sum()
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol)
        # Weighted
        wtd_tot_col = comstock.col_name_to_weighted(tot_col, comstock.weighted_energy_units)
        wtd_enduse_cols = [comstock.col_name_to_weighted(c, comstock.weighted_energy_units) for c in enduse_cols]
        sum_tot_col = comstock.data.get_column(wtd_tot_col).sum()
        sum_enduses = 0
        for c in wtd_enduse_cols:
            sum_enduses += comstock.data.get_column(c).sum()
        assert sum_enduses == pytest.approx(sum_tot_col, rel=engy_tol), f'Error in {tot_col}'