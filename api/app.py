from threadpoolctl import threadpool_limits
from sklearn.model_selection import HalvingGridSearchCV
from sklearn.ensemble import HistGradientBoostingClassifier

# 省略: 前処理Pipelineなど
search = HalvingGridSearchCV(
    estimator=pipe,
    param_grid={"clf__max_depth":[None,4,8],
                "clf__learning_rate":[0.05,0.1,0.2],
                "clf__max_leaf_nodes":[31,63]},
    scoring="roc_auc",
    cv=5, n_jobs=8,  # i7-9700ならここ
    verbose=1
)
with threadpool_limits(1):
    search.fit(Xtr, ytr)
