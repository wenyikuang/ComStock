

###### (Automatically generated documentation)

# add_heat_pump_rtu

## Description
Measure replaces existing packaged single-zone RTU system types with heat pump RTUs. Not applicable for water coil systems.

## Modeler Description
Modeler has option to set backup heat source, prevelence of heat pump oversizing, heat pump oversizing limit, and addition of energy recovery. This measure will work on unitary PSZ systems as well as single-zone, constant air volume air loop PSZ systems.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Backup Heat Type
Specifies if the backup heat fuel type is a gas furnace or electric resistance coil. If match original primary heating fuel is selected, the heating fuel type will match the primary heating fuel type of the original model. If electric resistance is selected, AHUs will get electric resistance backup.
**Name:** backup_ht_fuel_scheme,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["match_original_primary_heating_fuel", "electric_resistance_backup"]


### Maximum Performance Oversizing Factor
When heating design load exceeds cooling design load, the design cooling capacity of the unit will only be allowed to increase up to this factor to accomodate additional heating capacity. Oversizing the compressor beyond 25% can cause cooling cycling issues, even with variable speed compressors.
**Name:** performance_oversizing_factor,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Temperature to Sizing Heat Pump, F
Specifies temperature to size heating on. If design temperature for climate is higher than specified, program will use design temperature. Heat pump sizing will not exceed user-input oversizing factor.
**Name:** htg_sizing_option,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

**Choice Display Names** ["47F", "17F", "0F"]


### Cooling Upsizing Factor Estimate
RTU selection involves sizing up to unit that meets your capacity needs, which creates natural oversizing. This factor estimates this oversizing. E.G. the sizing calc may require 8.7 tons of cooling, but the size options are 7.5 tons and 10 tons, so you choose the 10 ton unit. A value of 1 means to upsizing.
**Name:** clg_oversizing_estimate,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Rated HP Heating to Cooling Ratio
At rated conditions, a compressor will generally have slightly more cooling capacity than heating capacity. This factor integrates this ratio into the unit sizing.
**Name:** htg_to_clg_hp_ratio,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add Energy Recovery?

**Name:** hr,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add Demand Control Ventilation?

**Name:** dcv,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add Economizer?

**Name:** econ,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false






