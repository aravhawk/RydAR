import sys; sys.path.insert(0,'/tmp/rydar_fars')
from loader import rd
import pandas as pd
A=[];V=[]
for y in range(2015,2025):
    a=rd(y,'accident.csv'); a['FARSYEAR']=y; A.append(a)
    v=rd(y,'vehicle.csv'); v['FARSYEAR']=y; V.append(v)
    print(y,len(a),len(v),flush=True)
pd.concat(A,ignore_index=True).to_pickle('/tmp/rydar_fars/raw/acc_all.pkl')
pd.concat(V,ignore_index=True).to_pickle('/tmp/rydar_fars/raw/veh_all.pkl')
